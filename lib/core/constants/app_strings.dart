/// 应用字符串常量
class AppStrings {
  AppStrings._();

  static const String appName = '享联';
  static const String appTagline = '跨设备无缝互联，文件即取即用，剪贴板跨屏同步。';

  // tabbar
  static const String tabbarHome = '首页';
  static const String tabbarFiles = '文件';
  static const String tabbarSettings = '设置';

  // 导航
  static const String navHome = '首页';
  static const String navFiles = '文件';
  static const String navClipboard = '剪贴板';
  static const String navSettings = '设置';

  // 首页
  static const String deviceDiscovery = '设备发现';
  static const String connectHint = '点击开启设备连接';
  static const String connectedHint = '已开启设备连接';
  static const String connectedDevices = '已连接过的设备';
  static const String connected = '已连接';
  static const String nearbyDevices = '附近设备';
  static const String online = '在线';
  static const String offline = '离线';
  static const String searchingNearbyDevices = '正在搜索附近设备…';
  static const String noNearbyDevices = '暂无附近设备';
  static const String noConnectionHint = '请确保其他设备已开启并连接同一网络';

  // 文件
  static const String fileBrowserTitle = '文件管理';
  static const String categoryImage = '图片';
  static const String categoryVideo = '视频';
  static const String categoryText = '文本';
  static const String categoryWord = 'Word';
  static const String categoryPpt = 'PPT';
  static const String categoryExcel = '表格';
  static const String categoryPdf = 'PDF';
  static const String categoryAudio = '音频';
  static const String categoryArchive = '压缩包';
  static const String categoryAll = '全部';

  // 文件 - 排序
  static const String sortByName = '文件名';
  static const String sortByTime = '时间轴';
  static const String sortBySize = '大小排序';
  static const String filterLabel = '筛选条件';

  // 文件 - 布局
  static const String layoutSingleColumn = '单列';
  static const String layoutDoubleColumn = '双列';
  static const String categoryDisplayDropdown = '下拉框';
  static const String categoryDisplayList = '横向列表';

  // 文件 - 添加分类
  static const String addCategory = '添加分类';
  static const String categoryName = '分类名称';
  static const String categoryIcon = '分类图标';
  static const String fileType = '文件类型';
  static const String selectAllFiles = '全选';
  static const String selectAllFilesSub = '匹配所有文件类型';
  static const String categoryNameHint = '请输入分类名称';
  static const String fileTypeHint = '搜索或输入文件后缀名';
  static const String saveCategory = '保存';
  static const String deleteCategory = '删除分类';

  // 设置
  static const String settingsTitle = '设置';
  static const String acceptConnections = '接受别人连接';
  static const String connectionPassword = '连接密码';
  static const String sharedContent = '共享内容';
  static const String clipboardSync = '剪贴板共享';

  // 设置 - 分组标题
  static const String settingsAppearance = '外观设置';
  static const String settingsConnection = '连接设置';
  static const String settingsShared = '共享设置';
  static const String settingsAbout = '关于软件';

  // 设置 - 导航项
  static const String navAppearance = '外观设置';
  static const String navConnection = '连接设置';
  static const String navShared = '共享设置';
  static const String navAbout = '关于软件';

  // 设置 - 副标题
  static const String acceptConnectionsSub = '允许其他设备发现并连接到本机';
  static const String connectionPasswordSub = '连接时需要输入密码';
  static const String sharedContentSub = '选择要共享的内容类型';
  static const String clipboardSyncSub = '跨设备同步剪贴板内容';

  // 设置 - 深色模式
  static const String darkMode = '深色模式';
  static const String themeSystem = '跟随系统';
  static const String themeLight = '浅色';
  static const String themeDark = '深色';

  // 设置 - 关于
  static const String aboutTitle = '关于软件';
  static const String aboutAppName = '应用名称';
  static const String aboutVersion = '版本';
  static const String aboutDeviceModel = '设备型号';
  static const String appVersion = '1.0.0';
  static const String close = '关闭';

  // 设置 - 共享内容
  static const String sharedAlbum = '相册';
  static const String sharedAlbumSub = '共享相册和相机中的所有图片';
  static const String sharedMusic = '音乐';
  static const String sharedMusicSub = '共享设备上的音乐文件';
  static const String sharedDocuments = '文档';
  static const String sharedDocumentsSub = '共享设备上的文档文件';
  static const String sharedDownloads = '下载';
  static const String sharedDownloadsSub = '共享设备上的下载文件';
  static const String sharedFolder = '文件夹';
  static const String sharedFolderSub = '共享指定文件夹';

  // 设置 - 共享内容 - 文件夹管理
  static const String addFolder = '添加文件夹';
  static const String removeFolder = '删除';
  static const String noFolders = '暂无共享文件夹';
  static const String selectFolder = '选择要共享的文件夹';
  static const String selectThisFolder = '选择此文件夹';
  static const String parentDir = '上一级';

  // 设置 - 共享内容 - 权限
  static const String permissionDeniedTitle = '需要权限';
  static const String permissionPhotosDesc = '需要相册访问权限才能共享图片，请在设置中开启相关权限';
  static const String permissionStorageDesc = '需要存储访问权限才能共享文件，请在设置中开启相关权限';

  // 设备连接
  static const String connecting = '连接中...';
  static const String connectedStatus = '已连接';
  static const String connectDeviceTitle = '连接设备';
  static const String confirmConnect = '确认连接';
  static const String cancelConnect = '取消';
  static const String passwordError = '密码错误，请重新输入';
  static const String connectFailed = '连接失败，请稍后重试';
  static const String peerRejected = '对端拒绝了连接';
  static const String removeDeviceTitle = '移除设备';
  static const String removeDeviceContent = '确定从已连接过列表中移除该设备？';
  static const String connectedToast = '已连接';
  static const String confirm = '确认';
  static const String disconnectTitle = '断开连接';
  static const String disconnectContent = '确定要断开与该设备的连接吗？';
  static const String disconnectBtn = '断开';
  static const String disconnectedToast = '已断开连接';
  static const String autoConnectedToast = '已自动连接';

  // 权限
  static const String permissionTitle = '需要网络权限';
  static const String permissionIOSDesc = '享联需要访问本地网络权限来发现附近设备，请在设置中开启本地网络权限';
  static const String permissionAndroidDesc = '享联需要网络权限来发现附近设备，请在设置中授予相关权限';
  static const String goToSettings = '去设置';
}
