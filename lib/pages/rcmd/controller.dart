import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/rcmd_discover.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class RcmdController extends CommonListController {
  late bool enableSaveLastData = Pref.enableSaveLastData;
  final bool appRcmd = Pref.appRcmd;
  int? lastRefreshAt;
  late bool savedRcmdTip = Pref.savedRcmdTip;

  @override
  bool get isEnd => false;

  @override
  void onInit() {
    super.onInit();
    page = 0;
    queryData();
  }

  @override
  Future<LoadingState> customGetData() async {
    if (Pref.useDiscoverRcmd && page == 0) {
      final rcmdRes = await VideoHttp.rcmdVideoListApp(freshIdx: 0);
      final discoverItems = await RcmdDiscoverEngine.fetch();

      if (rcmdRes case Success(:final response)) {
        if (discoverItems.isEmpty) return Success(response);
        return Success(_mixFeed(response, discoverItems));
      }
      return rcmdRes;
    }
    return appRcmd
        ? VideoHttp.rcmdVideoListApp(freshIdx: page)
        : VideoHttp.rcmdVideoList(freshIdx: page, ps: 20);
  }

  /// Insert [discover] items into [base] at [Pref.discoverMixInterval].
  static List<BaseSimpleVideoItemModel> _mixFeed(
    List base,
    List<BaseSimpleVideoItemModel> discover,
  ) {
    final interval = Pref.discoverMixInterval.clamp(2, 15);
    final mixed = <BaseSimpleVideoItemModel>[...base];
    var di = 0;
    for (var i = 0; i < mixed.length && di < discover.length; i++) {
      if ((i + 1) % interval == 0) {
        mixed.insert(i + 1, discover[di++]);
      }
    }
    mixed.addAll(discover.skip(di));
    return mixed;
  }

  @override
  bool handleError(String? errMsg) => enableSaveLastData;

  @override
  void handleListResponse(List dataList) {
    if (Pref.useDiscoverRcmd) {
      // In discover mode the data is already mixed in customGetData,
      // but we still track the marker so the "看到这里" card shows.
      if (enableSaveLastData && savedRcmdTip && page == 0) {
        if (loadingState.value case Success(:final response)) {
          if (response != null && response.isNotEmpty) {
            lastRefreshAt = dataList.length;
          }
        }
      }
      return;
    }
    if (enableSaveLastData && page == 0) {
      if (loadingState.value case Success(:final response)) {
        if (response != null && response.isNotEmpty) {
          if (savedRcmdTip) {
            lastRefreshAt = dataList.length;
          }
          if (response.length > 200) {
            dataList.addAll(response.take(50));
          } else {
            dataList.addAll(response);
          }
        }
      }
    }
  }

  @override
  Future<void> onRefresh() {
    page = 0;
    return queryData();
  }
}
