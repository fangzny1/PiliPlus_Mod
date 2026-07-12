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
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// Fetches videos from random followed UPs and related expansion,
/// wrapped as [BaseRcmdVideoItemModel] for direct use in [VideoCardV].
class RcmdDiscoverEngine {
  static final _random = Random();

  /// Returns up to [Pref.discoverBatchSize] items.
  static Future<List<BaseRcmdVideoItemModel>> fetch() async {
    final mids = await _getFollowMids();
    if (mids.isEmpty) return [];

    final upCount = Pref.discoverUpCount.clamp(1, 5);
    final batchSize = Pref.discoverBatchSize.clamp(5, 60);

    // ── 1. UP space videos ──
    final upVideos = <BaseRcmdVideoItemModel>[];
    for (final mid in _pickUps(mids, upCount)) {
      upVideos.addAll(await _fetchSpace(mid));
    }

    // ── 2. Related-video expansion from several seeds ──
    final relatedVideos = <BaseRcmdVideoItemModel>[];
    if (Pref.discoverRelatedExpand && upVideos.isNotEmpty) {
      final seedCount = min(upCount, upVideos.length);
      final seeds = _pickRandomItems(upVideos, seedCount);
      for (final seed in seeds) {
        if (seed.bvid != null) {
          relatedVideos.addAll(await _fetchRelated(seed.bvid!));
        }
        if (relatedVideos.length >= batchSize) break;
      }
    }

    // ── 3. Filter watched ──
    final watched = await _getWatchedBvids();
    upVideos.removeWhere((v) => watched.contains(v.bvid));
    relatedVideos.removeWhere((v) => watched.contains(v.bvid));

    // ── 4. Apply keyword filter ──
    if (RecommendFilter.enableFilter) {
      upVideos.removeWhere((v) => RecommendFilter.filterTitle(v.title));
      relatedVideos.removeWhere((v) => RecommendFilter.filterTitle(v.title));
    }

    // ── 5. Deduplicate by BVID ──
    final seen = <String>{};
    upVideos.removeWhere((v) {
      if (v.bvid == null) return false;
      return !seen.add(v.bvid!);
    });
    relatedVideos.removeWhere((v) {
      if (v.bvid == null) return false;
      return !seen.add(v.bvid!);
    });

    // ── 6. Interleave UP & related before shuffling ──
    //     (so the feed isn't all-space-then-all-related)
    final interleaved = <BaseRcmdVideoItemModel>[];
    var ui = 0, ri = 0;
    while (ui < upVideos.length || ri < relatedVideos.length) {
      if (ui < upVideos.length) interleaved.add(upVideos[ui++]);
      if (ri < relatedVideos.length) interleaved.add(relatedVideos[ri++]);
    }
    interleaved.shuffle(_random);
    return interleaved.take(batchSize).toList();
  }

  // ──────────────── helpers ────────────────

  static List<int> _pickUps(List<int> mids, int n) {
    if (mids.length <= n) return [...mids];
    final picked = <int>{};
    while (picked.length < n) {
      picked.add(mids[_random.nextInt(mids.length)]);
    }
    return picked.toList();
  }

  static List<T> _pickRandomItems<T>(List<T> items, int n) {
    if (items.length <= n) return [...items];
    final picked = <T>{};
    while (picked.length < n) {
      picked.add(items[_random.nextInt(items.length)]);
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

  static Future<List<DiscoverRcmdItem>> _fetchSpace(int mid) async {
    if (mid == 0) return [];
    final pn = _random.nextInt(3) + 1;
    final res = await MemberHttp.spaceArchive(
      type: ContributeType.video,
      mid: mid,
      pn: pn,
    );
    if (res case Success(:final response)) {
      return (response.item ?? [])
          .map((item) => DiscoverRcmdItem.fromSpace(item, mid))
          .toList();
    }
    return [];
  }

  static Future<List<DiscoverRcmdItem>> _fetchRelated(String bvid) async {
    if (bvid.isEmpty) return [];
    final res = await vhttp.VideoHttp.relatedVideoList(bvid: bvid);
    if (res case Success(:final response)) {
      return (response ?? [])
          .map((h) => DiscoverRcmdItem.fromHotVideo(h))
          .toList();
    }
    return [];
  }
}

/// Concrete [BaseRcmdVideoItemModel] so the video card renders correctly.
class DiscoverRcmdItem extends BaseRcmdVideoItemModel {
  DiscoverRcmdItem({
    required String titleVal,
    String? bvidVal,
    int? cidVal,
    String? coverVal,
    int durationVal = -1,
    required BaseOwner ownerVal,
    required BaseStat statVal,
  }) {
    title = titleVal;
    bvid = bvidVal;
    cid = cidVal;
    cover = coverVal;
    duration = durationVal;
    owner = ownerVal;
    stat = statVal;
    goto = 'av';
  }

  factory DiscoverRcmdItem.fromSpace(SpaceArchiveItem src, int ownerMid) {
    return DiscoverRcmdItem(
      titleVal: src.title,
      bvidVal: src.bvid,
      cidVal: src.cid,
      coverVal: src.cover,
      durationVal: src.duration,
      ownerVal: Owner(mid: ownerMid, name: src.owner.name),
      statVal: src.stat,
    );
  }

  factory DiscoverRcmdItem.fromHotVideo(HotVideoItemModel src) {
    return DiscoverRcmdItem(
      titleVal: src.title ?? '',
      bvidVal: src.bvid,
      cidVal: src.cid,
      coverVal: src.cover,
      durationVal: src.duration ?? -1,
      ownerVal: Owner(mid: src.owner.mid, name: src.owner.name),
      statVal: src.stat!,
    );
  }
}
