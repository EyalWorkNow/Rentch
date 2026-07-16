// ════════════════════════════════════════════════════════════════════════════
// GBDT — a compact, dependency-free gradient-boosted regression-tree learner
// ════════════════════════════════════════════════════════════════════════════
//
// A tiny LightGBM-flavoured model that TRAINS on-device from the app's own
// labelled behaviour (like/skip swipes). It complements the FTRL logistic
// learner (linear) and the hand-tuned static stump ensemble (fixed) by learning
// the NONLINEAR feature interactions that actually move this user — from a few
// hundred examples, in a handful of milliseconds, with no native deps.
//
// Design (kept deliberately small & bounded so it's cheap on a phone):
//   • Squared-loss gradient boosting: regress the [0,1] label directly, each
//     shallow tree fits the residual of the running prediction.
//   • Shallow regression trees (default depth 3), ≤30 trees, learning-rate 0.1.
//   • Greedy splits by VARIANCE REDUCTION (SSE gain) over a small set of
//     per-feature quantile candidate thresholds.
//   • Hard caps everywhere (trees / depth / min-leaf / samples / candidates) so
//     training on ~a few hundred rows is fast and allocation-light.
//   • predict() is clamped to [0,1]; toJson()/fromJson() persist the model.
// ════════════════════════════════════════════════════════════════════════════

class GbdtModel {
  GbdtModel({
    this.maxDepth = 3,
    this.maxTrees = 30,
    this.learningRate = 0.1,
    this.minLeaf = 5,
    this.minSamplesSplit = 10,
    this.maxSamples = 1500,
    this.splitCandidates = 12,
  });

  final int maxDepth; // tree depth cap (shallow ⇒ regularised + fast)
  final int maxTrees; // boosting rounds cap
  final double learningRate; // shrinkage per tree
  final int minLeaf; // min samples in a child to allow a split
  final int minSamplesSplit; // min samples in a node to attempt a split
  final int maxSamples; // train on at most this many (most-recent) rows
  final int splitCandidates; // quantile thresholds evaluated per feature

  double _base = 0.5; // mean label (the boosting starting point)
  final List<_GbNode> _trees = [];

  /// True once at least one tree has been fitted.
  bool get isTrained => _trees.isNotEmpty;

  int get treeCount => _trees.length;

  /// Fit the ensemble to features [X] (dense rows) and [0,1] labels [y].
  /// A degenerate call (empty / mismatched) is a safe no-op.
  void train(List<List<double>> X, List<double> y) {
    if (X.isEmpty || X.length != y.length) return;

    // Cap to the most-recent rows so training cost stays bounded.
    List<List<double>> xs = X;
    List<double> ys = y;
    if (X.length > maxSamples) {
      xs = X.sublist(X.length - maxSamples);
      ys = y.sublist(y.length - maxSamples);
    }
    final n = xs.length;
    final nf = xs.first.length;

    double base = 0;
    for (final v in ys) {
      base += v;
    }
    _base = base / n;
    _trees.clear();

    // Precompute quantile candidate thresholds per feature once (not per node).
    final candidates =
        List<List<double>>.generate(nf, (f) => _thresholdsFor(xs, f));

    final pred = List<double>.filled(n, _base);
    final allIdx = List<int>.generate(n, (i) => i);

    for (var t = 0; t < maxTrees; t++) {
      // Residual of squared loss = y − currentPrediction (the pseudo-target).
      final resid = List<double>.generate(n, (i) => ys[i] - pred[i]);
      final tree = _build(xs, resid, allIdx, candidates, 0);
      _trees.add(tree);
      for (var i = 0; i < n; i++) {
        pred[i] += learningRate * tree.predict(xs[i]);
      }
    }
  }

  /// Predicted relevance in [0,1] for a dense feature vector [x].
  double predict(List<double> x) {
    var v = _base;
    for (final tree in _trees) {
      v += learningRate * tree.predict(x);
    }
    return v.clamp(0.0, 1.0);
  }

  // Up to [splitCandidates] quantile thresholds of feature [f] (deduped).
  List<double> _thresholdsFor(List<List<double>> xs, int f) {
    final vals = <double>[for (final row in xs) row[f]];
    vals.sort();
    final out = <double>[];
    final k = splitCandidates;
    for (var q = 1; q <= k; q++) {
      final idx =
          ((vals.length * q) / (k + 1)).floor().clamp(0, vals.length - 1);
      final thr = vals[idx];
      if (out.isEmpty || (thr - out.last).abs() > 1e-9) out.add(thr);
    }
    return out;
  }

  _GbNode _build(
    List<List<double>> xs,
    List<double> resid,
    List<int> idx,
    List<List<double>> candidates,
    int depth,
  ) {
    final leafVal = _mean(resid, idx);
    if (depth >= maxDepth || idx.length < minSamplesSplit) {
      return _GbNode.leaf(leafVal);
    }

    final parentSse = _sse(resid, idx, leafVal);
    var bestGain = 0.0;
    var bestFeat = -1;
    var bestThr = 0.0;

    for (var f = 0; f < candidates.length; f++) {
      for (final thr in candidates[f]) {
        double sumL = 0, sumR = 0;
        int cntL = 0, cntR = 0;
        for (final i in idx) {
          if (xs[i][f] < thr) {
            sumL += resid[i];
            cntL++;
          } else {
            sumR += resid[i];
            cntR++;
          }
        }
        if (cntL < minLeaf || cntR < minLeaf) continue;
        final meanL = sumL / cntL;
        final meanR = sumR / cntR;
        double sse = 0;
        for (final i in idx) {
          final r = resid[i];
          if (xs[i][f] < thr) {
            final d = r - meanL;
            sse += d * d;
          } else {
            final d = r - meanR;
            sse += d * d;
          }
        }
        final gain = parentSse - sse;
        if (gain > bestGain) {
          bestGain = gain;
          bestFeat = f;
          bestThr = thr;
        }
      }
    }

    if (bestFeat < 0 || bestGain <= 1e-9) return _GbNode.leaf(leafVal);

    final left = <int>[];
    final right = <int>[];
    for (final i in idx) {
      (xs[i][bestFeat] < bestThr ? left : right).add(i);
    }
    return _GbNode.split(
      bestFeat,
      bestThr,
      _build(xs, resid, left, candidates, depth + 1),
      _build(xs, resid, right, candidates, depth + 1),
    );
  }

  double _mean(List<double> v, List<int> idx) {
    if (idx.isEmpty) return 0;
    double s = 0;
    for (final i in idx) {
      s += v[i];
    }
    return s / idx.length;
  }

  double _sse(List<double> v, List<int> idx, double mean) {
    double s = 0;
    for (final i in idx) {
      final d = v[i] - mean;
      s += d * d;
    }
    return s;
  }

  /// Serialize the learned model (base + trees + shrinkage) for persistence.
  Map<String, dynamic> toJson() => {
        'base': _base,
        'lr': learningRate,
        'trees': [for (final t in _trees) t.toJson()],
      };

  /// Restore a model from [toJson]. Missing/corrupt fields degrade to an empty
  /// (untrained) model, so a version-changed blob can never throw.
  factory GbdtModel.fromJson(Map<String, dynamic> j) {
    final lr = j['lr'];
    final m = GbdtModel(learningRate: lr is num ? lr.toDouble() : 0.1);
    final base = j['base'];
    m._base = base is num ? base.toDouble() : 0.5;
    final trees = j['trees'];
    if (trees is List) {
      for (final t in trees) {
        if (t is Map) {
          m._trees.add(_GbNode.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }
    return m;
  }
}

// A single node of a regression tree: either a leaf (holds a value) or a split
// (feature/threshold with two children). Kept as one class for compact JSON.
class _GbNode {
  _GbNode.leaf(this.value)
      : feature = -1,
        threshold = 0,
        left = null,
        right = null;

  _GbNode.split(this.feature, this.threshold, this.left, this.right)
      : value = 0;

  final int feature;
  final double threshold;
  final double value;
  final _GbNode? left;
  final _GbNode? right;

  bool get isLeaf => left == null;

  double predict(List<double> x) {
    var node = this;
    while (!node.isLeaf) {
      final f = node.feature;
      final goLeft = f >= 0 && f < x.length && x[f] < node.threshold;
      node = goLeft ? node.left! : node.right!;
    }
    return node.value;
  }

  Map<String, dynamic> toJson() => isLeaf
      ? {'v': value}
      : {'f': feature, 't': threshold, 'l': left!.toJson(), 'r': right!.toJson()};

  factory _GbNode.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('l') && j.containsKey('r')) {
      final f = j['f'];
      final t = j['t'];
      return _GbNode.split(
        f is num ? f.toInt() : -1,
        t is num ? t.toDouble() : 0.0,
        _GbNode.fromJson(Map<String, dynamic>.from(j['l'])),
        _GbNode.fromJson(Map<String, dynamic>.from(j['r'])),
      );
    }
    final v = j['v'];
    return _GbNode.leaf(v is num ? v.toDouble() : 0.0);
  }
}
