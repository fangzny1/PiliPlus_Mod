import 'dart:math';

import 'package:PiliPlus/http/follow.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/member.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart' as vhttp;
import 'package:PiliPlus/models/common/member/contribute_type.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';

/// Fetches a batch of videos from random followed UPs and related expansion.
/// Used by [RcmdController] to inject into the app rcmd feed.
class RcmdDiscoverEngine {
  static final _random = Random();

  /// Returns up to [count] discover videos (default 20).
  static Future<List<BaseSimpleVideoItemModel>> fetch({
    int count = 20,
  }) async {
    final mids = await _getFollowMids();
    if (mids.isEmpty) return [];

    final pool = <BaseSimpleVideoItemModel>[];
    for (final mid in _pickUps(mids, 2)) {
      final videos = await _fetchSpace(mid);
      pool.addAll(videos);
    }
    if (pool.isEmpty) return [];

    // Use one as seed for related expansion
    final seed = pool[_random.nextInt(min(pool.length, 2))];
    final related = await _fetchRelated(seed.bvid ?? '');
    pool.addAll(related);

    // Filter watched
    final watched = await _getWatchedBvids();
    pool.removeWhere((v) => v.bvid != null && watched.contains(v.bvid));

    // Apply keyword filter
    if (RecommendFilter.enableFilter) {
      pool.removeWhere((v) => RecommendFilter.filterTitle(v.title));
    }

    pool.shuffle(_random);
    return pool.take(count).toList();
  }

  static List<int> _pickUps(List<int> mids, int n) {
    if (mids.length <= n) return [...mids];
    final picked = <int>{};
    while (picked.length < n) {
      picked.add(mids[_random.nextInt(mids.length)]);
    }
    return picked.toList();
  }

  // ──────────────── caches ────────────────

  static final _cache = GStorage.localCache;

  static bool _cacheValid(String timeKey, Duration maxAge) {
    final ts = _cache.get(timeKey, defaultValue: 0) as int;
    if (ts == 0) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < maxAge.inMilliseconds;
  }

  static Future<List<int>> _getFollowMids() async {
    const key = 'disc_follow_mids';
    const timeKey = 'disc_follow_time';

    if (_cacheValid(timeKey, const Duration(minutes: 30))) {
      final cached = _cache.get(key) as List?;
      if (cached != null && cached.isNotEmpty) return cached.cast<int>();
    }

    final mid = Accounts.main.mid;
    if (mid == 0) return [];

    final res = await FollowHttp.followings(vmid: mid, pn: 1, ps: 50);
    if (res case Success(:final response)) {
      final list = response.list;
      if (list != null && list.isNotEmpty) {
        final mids = <int>[];
        for (final f in list) {
          final m = f.mid;
          if (m != null && m != 0) mids.add(m);
        }
        _cache.put(key, mids);
        _cache.put(timeKey, DateTime.now().millisecondsSinceEpoch);
        return mids;
      }
    }
    return [];
  }

  static Future<Set<String>> _getWatchedBvids() async {
    const key = 'disc_history';
    const timeKey = 'disc_history_time';

    if (_cacheValid(timeKey, const Duration(minutes: 5))) {
      final cached = _cache.get(key) as List?;
      if (cached != null) return cached.cast<String>().toSet();
    }

    final bvids = <String>{};
    final res = await UserHttp.historyList(type: 'archive');
    if (res case Success(:final response)) {
      for (final item in response.list ?? <Never>[]) {
        if (item.history?.bvid case final bvid?) bvids.add(bvid);
      }
    }
    _cache.put(key, bvids.toList());
    _cache.put(timeKey, DateTime.now().millisecondsSinceEpoch);
    return bvids;
  }

  // ──────────────── API calls ────────────────

  static Future<List<SpaceArchiveItem>> _fetchSpace(int mid) async {
    if (mid == 0) return [];
    final pn = _random.nextInt(3) + 1;
    final res = await MemberHttp.spaceArchive(
      type: ContributeType.video,
      mid: mid,
      pn: pn,
    );
    if (res case Success(:final response)) {
      final items = response.item ?? [];
      // SpaceArchiveItem hardcodes owner.mid = 0; fix it
      for (final item in items) {
        item.owner = Owner(mid: mid, name: item.owner.name);
      }
      return items;
    }
    return [];
  }

  static Future<List<BaseSimpleVideoItemModel>> _fetchRelated(
    String bvid,
  ) async {
    if (bvid.isEmpty) return [];
    final res = await vhttp.VideoHttp.relatedVideoList(bvid: bvid);
    if (res case Success(:final response)) {
      return (response ?? [])
          .map((h) => _WrappedHotVideo(h))
          .toList();
    }
    return [];
  }
}

class _WrappedHotVideo extends BaseSimpleVideoItemModel {
  _WrappedHotVideo(HotVideoItemModel src) {
    title = src.title ?? '';
    bvid = src.bvid;
    cid = src.cid;
    cover = src.cover;
    duration = src.duration ?? -1;
    owner = Owner(mid: src.owner!.mid, name: src.owner?.name);
    stat = src.stat ?? Stat.fromJson({'view': 0, 'like': 0, 'danmaku': 0});
  }
}
