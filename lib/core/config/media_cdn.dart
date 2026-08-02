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

  static const String _marker = '.amazonaws.com/';

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
