/// Rewrites our S3 media URLs to the CloudFront edge so images / panoramas /
/// scans are served cached from the CDN — ~90% less S3 origin egress and lower
/// latency (edge-served, incl. the Tel-Aviv edge). No-op for anything that isn't
/// one of OUR public S3 objects: external CDNs (Yad2 / Unsplash), local file
/// paths, already-CDN URLs, and SIGNED S3 URLs (which must keep their signature).
class MediaCdn {
  MediaCdn._();

  /// Our public media bucket host fragment (matches both
  /// `<bucket>.s3.us-east-1.amazonaws.com` and the region-less `<bucket>.s3....`).
  static const String _bucketHostFragment = 'rentch-media-543897290879.s3';

  /// The CloudFront distribution domain in front of that bucket. Override at
  /// build time with --dart-define=MEDIA_CDN_HOST=<domain> if it ever changes.
  static const String _cdnHost = String.fromEnvironment(
    'MEDIA_CDN_HOST',
    defaultValue: 'd1fdecs29tmtug.cloudfront.net',
  );

  /// The thumbnail CDN (on-the-fly resize Lambda behind CloudFront, keyed by ?w).
  static const String _thumbHost = String.fromEnvironment(
    'MEDIA_THUMB_HOST',
    defaultValue: 'd2q8n06j1ozb0e.cloudfront.net',
  );

  static const String _marker = '.amazonaws.com/';

  /// A resized-on-the-fly thumbnail URL for one of OUR S3 images at ~[width] px
  /// (served + cached by the thumbnail CDN; never upscales). Width snaps to a few
  /// buckets so the CDN caches a handful of sizes, not one per pixel. Non-S3 /
  /// local / signed URLs fall through to [url] (full CDN / passthrough).
  static String thumb(String? src, int width) {
    if (src == null || src.isEmpty) return src ?? '';
    if (!src.contains(_bucketHostFragment)) return url(src);
    if (src.contains('X-Amz-')) return src;
    final i = src.indexOf(_marker);
    if (i < 0) return url(src);
    final key = src.substring(i + _marker.length);
    return 'https://$_thumbHost/thumb/$key?w=${_bucket(width)}';
  }

  static int _bucket(int w) {
    for (final b in const [200, 400, 600, 900, 1200]) {
      if (w <= b) return b;
    }
    return 1600;
  }

  static String url(String? src) {
    if (src == null || src.isEmpty) return src ?? '';
    // Not one of our S3 objects → leave untouched (external CDN / local file).
    if (!src.contains(_bucketHostFragment)) return src;
    // Signed URLs must keep the exact host their signature was computed for.
    if (src.contains('X-Amz-')) return src;
    final i = src.indexOf(_marker);
    if (i < 0) return src;
    final key = src.substring(i + _marker.length);
    return 'https://$_cdnHost/$key';
  }
}
