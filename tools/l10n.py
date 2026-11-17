#!/usr/bin/env python3
"""UI 文案的唯一来源。

用法：
  python3 tools/l10n.py generate   # 生成 SeichiJunrei/Resources/<lang>.lproj/*.strings
  python3 tools/l10n.py check      # 校验：代码里用到的 key 在所有语言中都存在、占位符一致、生成文件是最新的

每条：key: (zh-Hans, zh-Hant, ja, en, ko)
"""
import os, re, sys, glob

LANGS = ["zh-Hans", "zh-Hant", "ja", "en", "ko"]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "SeichiJunrei", "Resources")

S = {
  # 八方位
  "compass.0": ("北", "北", "北", "north", "북"),
  "compass.1": ("东北", "東北", "北東", "northeast", "북동"),
  "compass.2": ("东", "東", "東", "east", "동"),
  "compass.3": ("东南", "東南", "南東", "southeast", "남동"),
  "compass.4": ("南", "南", "南", "south", "남"),
  "compass.5": ("西南", "西南", "南西", "southwest", "남서"),
  "compass.6": ("西", "西", "西", "west", "서"),
  "compass.7": ("西北", "西北", "北西", "northwest", "북서"),
  # 作品类型
  "media.anime": ("日漫", "動漫", "アニメ", "Anime", "애니"),
  "media.animeFilm": ("日漫", "動漫", "アニメ映画", "Anime film", "극장판 애니"),
  "media.film": ("日影", "日片", "映画", "Film", "일본 영화"),
  "media.filmForeign": ("电影", "電影", "映画", "Film", "영화"),
  "media.drama": ("日剧", "日劇", "ドラマ", "J-drama", "일드"),
  # 通用格式
  "format.workTitle": ("《%@》", "《%@》", "『%@』", "%@", "「%@」"),
  "format.sceneTitle": ("「%@」", "「%@」", "「%@」", "“%@”", "‘%@’"),
  "format.workWithLocalized": ("%@（%@）", "%@（%@）", "%@（%@）", "%@ (%@)", "%@ (%@)"),
  "common.done": ("完成", "完成", "完了", "Done", "완료"),
  "common.close": ("关闭", "關閉", "閉じる", "Close", "닫기"),
  # 转身指引
  "guide.aligned": ("就是这里！你正站在名场面之中", "就是這裡！你正站在名場面之中", "ここだ！今、名シーンの中にいる",
                    "This is it! You're standing inside the scene", "바로 여기! 지금 명장면 속에 서 있어요"),
  "guide.tiltUp": ("方向对了，再稍微抬头 %ld°", "方向對了，再稍微抬頭 %ld°", "向きはOK、あと%ld°上を向いて",
                   "Right direction — tilt up %ld°", "방향은 맞아요. %ld° 위로 올려 보세요"),
  "guide.tiltDown": ("方向对了，再稍微低头 %ld°", "方向對了，再稍微低頭 %ld°", "向きはOK、あと%ld°下を向いて",
                     "Right direction — tilt down %ld°", "방향은 맞아요. %ld° 아래로 내려 보세요"),
  "guide.left": ("向左转 %ld°", "向左轉 %ld°", "左に%ld°回って", "Turn left %ld°", "왼쪽으로 %ld° 돌아요"),
  "guide.right": ("向右转 %ld°", "向右轉 %ld°", "右に%ld°回って", "Turn right %ld°", "오른쪽으로 %ld° 돌아요"),
  # 相机
  "camera.failed": ("拍照失败", "拍照失敗", "撮影に失敗しました", "Couldn't take the photo", "촬영에 실패했어요"),
  "camera.saved": ("已保存到相册 📸", "已儲存到相簿 📸", "写真に保存しました 📸", "Saved to Photos 📸", "사진에 저장했어요 📸"),
  "camera.saveFailed": ("保存失败：请在设置中允许访问相册", "儲存失敗：請在設定中允許取用相簿",
                        "保存できませんでした。設定で写真へのアクセスを許可してください",
                        "Couldn't save. Allow Photos access in Settings.", "저장하지 못했어요. 설정에서 사진 접근을 허용해 주세요"),
  # 通知
  "notif.title": ("你已来到%@的圣地", "你已來到%@的聖地", "%@の聖地に到着しました",
                  "You've reached a spot from %@", "%@의 성지에 도착했어요"),
  "notif.body": ("%@就在附近，打开 App 寻找名场面的视角吧！", "%@就在附近，打開 App 尋找名場面的視角吧！",
                 "%@はすぐ近く。アプリを開いて名シーンの視点を探そう！",
                 "%@ is right nearby — open the app to find the exact shot!",
                 "%@이(가) 바로 근처예요. 앱을 열어 명장면의 시점을 찾아보세요!"),
  # 数据
  "data.missing": ("找不到圣地数据", "找不到聖地資料", "聖地データが見つかりません", "Spot data not found", "성지 데이터를 찾을 수 없어요"),
  "data.parseFailed": ("圣地数据解析失败：%@", "聖地資料解析失敗：%@", "聖地データの読み込みに失敗しました：%@",
                       "Couldn't read spot data: %@", "성지 데이터를 읽지 못했어요: %@"),
  "data.loadFailedTitle": ("数据加载失败", "資料載入失敗", "データを読み込めませんでした", "Couldn't load data", "데이터를 불러오지 못했어요"),
  # 庆祝
  "celebrate.title": ("✨ 就是这个画面！✨", "✨ 就是這個畫面！✨", "✨ この景色だ！✨", "✨ This is the shot! ✨", "✨ 바로 이 장면! ✨"),
  "celebrate.subtitle": ("此刻，你就是%@的主角", "此刻，你就是%@的主角", "今この瞬間、あなたが%@の主人公",
                         "Right now, you're the star of %@", "지금 이 순간, 당신이 %@의 주인공이에요"),
  "celebrate.photo": ("拍照留念", "拍照留念", "記念に撮影", "Take a photo", "기념 사진 찍기"),
  "celebrate.continue": ("继续欣赏", "繼續欣賞", "このまま眺める", "Keep looking", "계속 감상하기"),
  # 地图首页
  "map.title": ("圣地巡礼", "聖地巡禮", "聖地巡礼", "Seichi Junrei", "성지순례"),
  "map.searchPrompt": ("搜索日漫、日剧、日影的名字", "搜尋動漫、日劇、日片的名稱", "アニメ・ドラマ・映画のタイトルで検索", "Search anime, J-dramas, movies", "애니·일드·일본 영화 제목 검색"),
  "map.queryResults": ("「%@」的搜索结果", "「%@」的搜尋結果", "「%@」の検索結果", "Results for “%@”", "‘%@’ 검색 결과"),
  "map.queryResultsCount": ("%ld 部作品 · %ld 个名场面", "%ld 部作品 · %ld 個名場面", "%ld作品 · 名シーン%ld件",
                            "%ld titles · %ld scenes", "작품 %ld편 · 명장면 %ld곳"),
  "map.allScenes": ("全部名场面", "全部名場面", "すべての名シーン", "All scenes", "모든 명장면"),
  "map.noResults": ("没有找到「%@」相关的名场面", "找不到「%@」相關的名場面", "「%@」に一致する名シーンはありません",
                    "No scenes found for “%@”", "‘%@’에 해당하는 명장면이 없어요"),
  "map.allWorks": ("全部作品", "全部作品", "すべての作品", "All titles", "모든 작품"),
  "map.searchResults": ("搜索结果", "搜尋結果", "検索結果", "Results", "검색 결과"),
  "map.typeScenes": ("%@的名场面", "%@的名場面", "%@の名シーン", "%@ scenes", "%@ 명장면"),
  "map.nearestScenes": ("离你最近的名场面", "離你最近的名場面", "いちばん近い名シーン", "Closest scenes", "가장 가까운 명장면"),
  "map.nearbyScenes": ("附近的名场面", "附近的名場面", "近くの名シーン", "Scenes nearby", "근처 명장면"),
  "map.focusSubtitle": ("%@ · %ld 个名场面", "%@ · %ld 個名場面", "%@ · 名シーン%ld件", "%@ · %ld scenes", "%@ · 명장면 %ld곳"),
  "map.all": ("全部", "全部", "すべて", "All", "전체"),
  "map.showAll": ("显示全部名场面", "顯示全部名場面", "すべての名シーンを表示", "Show all scenes", "모든 명장면 보기"),
  "map.arrivedTitle": ("你就站在名场面里！", "你就站在名場面裡！", "今、名シーンの中にいる！",
                       "You're standing in the scene!", "지금 명장면 속에 서 있어요!"),
  "map.needLocation": ("需要定位权限才能发现附近的圣地，点此前往设置", "需要定位權限才能發現附近的聖地，點此前往設定",
                       "近くの聖地を探すには位置情報の許可が必要です。タップして設定を開く",
                       "Location access is needed to find nearby spots. Tap to open Settings.",
                       "근처 성지를 찾으려면 위치 권한이 필요해요. 탭해서 설정 열기"),
  "map.alwaysPrompt": ("开启“始终允许”定位，靠近圣地时提醒你", "開啟「永遠允許」定位，靠近聖地時提醒你",
                       "位置情報を「常に許可」にすると、聖地の近くで通知します",
                       "Allow location “Always” to get alerts near spots",
                       "위치를 ‘항상 허용’으로 하면 성지 근처에서 알려 드려요"),
  "map.dontShowAgain": ("不再提示", "不再提示", "今後表示しない", "Don't show again", "다시 보지 않기"),
  # 列表
  "list.type": ("类型", "類型", "種類", "Type", "유형"),
  "list.searchPrompt": ("日漫 / 日剧 / 日影名称", "動漫 / 日劇 / 日片名稱", "アニメ・ドラマ・映画名", "Anime / J-drama / movie title", "애니 / 일드 / 영화 제목"),
  # 名场面模式
  "scene.calibrating": ("正在校准方向…\\n请把手机竖起，在空中画几次 ∞ 字", "正在校準方向…\\n請把手機豎起，在空中畫幾次 ∞ 字",
                        "方位を調整中…\\nスマホを立てて、空中で ∞ を何回か描いてください",
                        "Calibrating direction…\\nHold your phone upright and draw ∞ in the air a few times",
                        "방향을 보정하는 중…\\n휴대폰을 세우고 공중에 ∞ 모양을 몇 번 그려 주세요"),
  "scene.story": ("剧情", "劇情", "ストーリー", "Story", "줄거리"),
  "scene.spotDirection": ("圣地在你的%@方", "聖地在你的%@方", "聖地は%@の方向です", "The spot is to the %@", "성지는 %@쪽에 있어요"),
  "scene.walkCloser": ("走到距离机位 %ld 米以内，就会开启名场面取景", "走到距離機位 %ld 公尺以內，就會開啟名場面取景",
                       "撮影位置から%ldm以内に近づくと、名シーンモードが始まります",
                       "Get within %ld m of the spot to start the scene view",
                       "촬영 위치에서 %ldm 이내로 가면 명장면 모드가 시작돼요"),
  "scene.locating": ("正在获取你的位置…", "正在取得你的位置…", "現在地を取得中…", "Finding your location…", "위치를 확인하는 중…"),
  "scene.straightAhead": ("朝前方直走", "朝前方直走", "まっすぐ進んで", "Go straight ahead", "앞으로 쭉 가세요"),
  "scene.behind": ("在你身后，请转身", "在你身後，請轉身", "後ろにあります。振り返って", "It's behind you — turn around", "뒤쪽에 있어요. 돌아서세요"),
  "scene.aheadRight": ("向右前方前进", "向右前方前進", "右前方へ進んで", "Head forward and to the right", "오른쪽 앞으로 가세요"),
  "scene.aheadLeft": ("向左前方前进", "向左前方前進", "左前方へ進んで", "Head forward and to the left", "왼쪽 앞으로 가세요"),
  "scene.weakCompass": ("罗盘信号较弱，远离金属物体或画 ∞ 字校准", "羅盤訊號較弱，請遠離金屬物體或畫 ∞ 字校準",
                        "コンパスの精度が低いです。金属から離れるか ∞ を描いて調整してください",
                        "Weak compass signal — move away from metal or draw ∞ to calibrate",
                        "나침반 신호가 약해요. 금속에서 떨어지거나 ∞를 그려 보정하세요"),
  # 详情
  "detail.atSpot": ("你就站在这个名场面的机位上", "你就站在這個名場面的機位上", "この名シーンの撮影位置に立っています",
                    "You're standing at this scene's spot", "지금 이 명장면의 촬영 위치에 있어요"),
  "detail.distance": ("距离 %@ · 在你的%@方", "距離 %@ · 在你的%@方", "距離 %@ · %@の方向", "%@ away · to the %@", "%@ 거리 · %@쪽"),
  "detail.enterScene": ("走进这一幕！", "走進這一幕！", "このシーンの中へ！", "Step into the scene!", "이 장면 속으로!"),
  "detail.startGuide": ("复现这一幕", "重現這一幕", "このシーンを再現する", "Recreate this scene", "이 장면 재현하기"),
  "detail.story": ("剧情背景", "劇情背景", "ストーリー", "Story", "줄거리"),
  "detail.tips": ("巡礼须知", "巡禮須知", "巡礼マナー・注意", "Good to know", "알아 두세요"),
  "detail.openMaps": ("导航", "導航", "経路", "Directions", "길찾기"),
  "detail.unverified": ("该地点的机位坐标与朝向为参考值，尚未经过实地校准。", "此地點的機位座標與朝向為參考值，尚未經過實地校準。",
                        "この地点の撮影位置と向きは参考値で、現地での確認はまだです。",
                        "This spot's position and direction are approximate and haven't been verified on site.",
                        "이 장소의 촬영 위치와 방향은 참고값이며 아직 현장에서 확인되지 않았어요."),
  "detail.debugSimulate": ("（调试）模拟站在这个机位", "（除錯）模擬站在這個機位", "（デバッグ）この撮影位置にいることにする",
                           "(Debug) Pretend I'm at this spot", "(디버그) 이 위치에 있는 것으로 설정"),
  "detail.changeImage": ("更换名场面截图", "更換名場面截圖", "名シーン画像を変更", "Change scene image", "명장면 이미지 변경"),
  "detail.addImage": ("添加名场面截图", "新增名場面截圖", "名シーン画像を追加", "Add scene image", "명장면 이미지 추가"),
  "detail.deleteImage": ("删除名场面截图", "刪除名場面截圖", "名シーン画像を削除", "Delete scene image", "명장면 이미지 삭제"),
  "detail.searchWeb": ("网上搜这一幕", "上網搜這一幕", "ウェブで検索", "Search online", "웹에서 검색"),
  "detail.imageHint": ("截图只保存在你的手机上，到达机位后会叠加在相机画面中，帮你对准同一个构图。",
                       "截圖只會儲存在你的手機上，到達機位後會疊加在相機畫面中，幫你對準同一個構圖。",
                       "画像はこの端末にだけ保存されます。撮影位置に着くとカメラ映像に重ねて表示され、同じ構図に合わせやすくなります。",
                       "The image stays on your phone. At the spot it's overlaid on the camera so you can match the framing.",
                       "이미지는 휴대폰에만 저장돼요. 촬영 위치에 도착하면 카메라 화면에 겹쳐 보여 같은 구도를 맞추기 쉬워요."),
  "detail.imageSet": ("已设置名场面截图 ✓", "已設定名場面截圖 ✓", "名シーン画像を設定しました ✓", "Scene image set ✓", "명장면 이미지를 설정했어요 ✓"),
  "detail.imageFailed": ("图片读取失败，请换一张试试", "圖片讀取失敗，請換一張試試", "画像を読み込めませんでした。別の画像をお試しください",
                         "Couldn't load that image. Try another one.", "이미지를 불러오지 못했어요. 다른 이미지를 선택해 주세요"),
  # 付费
  "paywall.title": ("解锁全部名场面", "解鎖全部名場面", "すべての名シーンを解放", "Unlock every scene", "모든 명장면 잠금 해제"),
  "paywall.subtitle": ("站在机位上转身对准，成为名场面的主角", "站在機位上轉身對準，成為名場面的主角",
                       "撮影位置で振り向いて、名シーンの主人公になろう", "Stand on the spot, turn, and step into the scene",
                       "촬영 위치에서 돌아서서 명장면의 주인공이 되어 보세요"),
  "paywall.feature1": ("不限次数的名场面取景与转身指引", "不限次數的名場面取景與轉身指引", "名シーンモードと向きのガイドが使い放題",
                       "Unlimited scene view and turn guidance", "명장면 모드와 방향 안내 무제한"),
  "paywall.feature2": ("对准瞬间的庆祝特效与拍照留念", "對準瞬間的慶祝特效與拍照留念", "ぴったり合った瞬間の演出と記念撮影",
                       "Celebration and a keepsake photo when you line up", "딱 맞춘 순간의 축하 효과와 기념 사진"),
  "paywall.feature3": ("地图、搜索、剧情介绍永久免费", "地圖、搜尋、劇情介紹永久免費", "マップ・検索・ストーリー紹介はずっと無料",
                       "Map, search and stories stay free", "지도·검색·줄거리는 계속 무료"),
  "paywall.pass7": ("7 天旅行通行证", "7 天旅行通行證", "7日間トラベルパス", "7-day Trip Pass", "7일 여행 패스"),
  "paywall.pass30": ("30 天旅行通行证", "30 天旅行通行證", "30日間トラベルパス", "30-day Trip Pass", "30일 여행 패스"),
  "paywall.lifetime": ("终身解锁", "終身解鎖", "買い切り（ずっと使える）", "Lifetime unlock", "평생 이용권"),
  "paywall.passNote": ("到期不会自动续费，可叠加购买", "到期不會自動續費，可疊加購買", "自動更新なし・重ねて購入すると延長",
                       "Doesn't auto-renew · buying again extends it", "자동 갱신 없음 · 추가 구매 시 기간 연장"),
  "paywall.lifetimeNote": ("一次购买，永久使用", "一次購買，永久使用", "一度の購入でずっと使える", "Pay once, yours forever", "한 번 구매로 영구 이용"),
  "paywall.bestValue": ("最划算", "最划算", "いちばんお得", "Best value", "가장 알뜰"),
  "paywall.restore": ("恢复购买", "回復購買", "購入を復元", "Restore purchases", "구매 복원"),
  "paywall.retry": ("重试", "重試", "再試行", "Try again", "다시 시도"),
  "paywall.unavailable": ("暂时无法连接 App Store，请稍后再试", "暫時無法連線 App Store，請稍後再試",
                          "App Store に接続できません。しばらくしてからお試しください",
                          "Can't reach the App Store right now. Please try again later.",
                          "지금은 App Store에 연결할 수 없어요. 잠시 후 다시 시도해 주세요"),
  "paywall.purchaseFailed": ("购买未完成：%@", "購買未完成：%@", "購入できませんでした：%@", "Purchase didn't go through: %@", "구매가 완료되지 않았어요: %@"),
  "paywall.pending": ("购买等待确认（例如等待家长批准）", "購買等待確認（例如等待家長同意）", "購入の承認待ちです（保護者の承認など）",
                      "Purchase is waiting for approval", "구매 승인을 기다리는 중이에요"),
  "paywall.restored": ("已恢复购买", "已回復購買", "購入を復元しました", "Purchases restored", "구매를 복원했어요"),
  "paywall.nothingToRestore": ("没有可恢复的购买", "沒有可回復的購買", "復元できる購入はありません", "No purchases to restore", "복원할 구매가 없어요"),
  "status.beta": ("公测期间全部功能免费", "公測期間所有功能免費", "公開テスト中はすべて無料",
                  "Everything is free during the public beta", "공개 테스트 기간 동안 모두 무료"),
  "status.lifetime": ("已终身解锁", "已終身解鎖", "買い切り版をご利用中", "Lifetime unlocked", "평생 이용 중"),
  "status.passUntil": ("通行证有效期至 %@", "通行證有效期至 %@", "パスの有効期限：%@", "Pass valid until %@", "패스 유효 기간: %@까지"),
  "status.freeRemaining": ("还可免费体验 %ld 处名场面", "還可免費體驗 %ld 處名場面", "無料であと%ld件の名シーンを体験できます",
                           "%ld free scenes left", "무료 명장면 %ld곳 남았어요"),
  "locked.title": ("免费体验次数已用完", "免費體驗次數已用完", "無料体験の回数を使い切りました", "You've used your free scenes", "무료 체험을 모두 사용했어요"),
  "locked.body": ("购买旅行通行证或终身解锁，就能在这里转身对准名场面。", "購買旅行通行證或終身解鎖，就能在這裡轉身對準名場面。",
                  "トラベルパスか買い切りで、この場所の名シーンを体験しよう。",
                  "Get a Trip Pass or the lifetime unlock to line up this scene.",
                  "여행 패스나 평생 이용권으로 이 명장면을 체험해 보세요."),
  "locked.cta": ("查看方案", "查看方案", "プランを見る", "See options", "요금제 보기"),
  # 分享
  "share.badge": ("巡礼达成", "巡禮達成", "巡礼達成", "Pilgrimage complete", "순례 완료"),
  "share.stamp": ("巡礼达成", "巡禮達成", "巡礼達成", "VISITED", "순례완료"),
  "share.headline": ("我站在了这个名场面里", "我站在了這個名場面裡", "あの名シーンの場所に、今いる",
                     "I stood right inside this scene", "나는 이 명장면 속에 서 있었다"),
  "share.labelScene": ("作中", "作品中", "作中", "IN THE STORY", "작품 속"),
  "share.labelReal": ("现实", "現實", "現実", "FOR REAL", "현실"),
  "share.facing": ("朝向%@ %ld°", "朝向%@ %ld°", "%@向き %ld°", "Facing %@ %ld°", "%@쪽 %ld°"),
  "share.text": ("我来到了%@%@的现场！", "我來到了%@%@的現場！", "%@%@の聖地に来た！",
                 "I made it to the real-life spot of %@ %@!", "%@ %@의 현장에 왔어요!"),
  "share.hashtagPilgrimage": ("圣地巡礼", "聖地巡禮", "聖地巡礼", "AnimePilgrimage", "성지순례"),
  "share.hashtagApp": ("SeichiJunrei", "SeichiJunrei", "SeichiJunrei", "SeichiJunrei", "SeichiJunrei"),
  "share.title": ("分享巡礼卡", "分享巡禮卡", "巡礼カードをシェア", "Share your pilgrimage", "순례 카드 공유"),
  "share.layout": ("版式", "版式", "レイアウト", "Layout", "레이아웃"),
  "share.layoutSingle": ("现场照片", "現場照片", "現地の写真", "My photo", "현장 사진"),
  "share.layoutCompare": ("作中 vs 现实", "作品中 vs 現實", "作中 vs 現実", "Story vs real", "작품 vs 현실"),
  "share.share": ("分享", "分享", "シェア", "Share", "공유"),
  "share.save": ("保存到相册", "儲存到相簿", "写真に保存", "Save to Photos", "사진에 저장"),
  "share.noPhotoHint": ("还没有现场照片：在名场面模式对准后点“拍照留念”，照片就会放进卡片。",
                        "還沒有現場照片：在名場面模式對準後點「拍照留念」，照片就會放進卡片。",
                        "まだ現地の写真がありません。名シーンモードで合わせたあと「記念に撮影」をタップすると、カードに入ります。",
                        "No photo yet — line up the scene and tap “Take a photo” to put it on the card.",
                        "아직 현장 사진이 없어요. 명장면 모드에서 맞춘 뒤 ‘기념 사진 찍기’를 누르면 카드에 들어가요."),
  "share.noSceneImageHint": ("在详情页添加名场面截图，就能生成“作中 vs 现实”的对比卡。",
                             "在詳情頁新增名場面截圖，就能產生「作品中 vs 現實」的對比卡。",
                             "詳細画面で名シーン画像を追加すると「作中 vs 現実」の比較カードが作れます。",
                             "Add a scene image on the details page to make a “story vs real” card.",
                             "상세 화면에서 명장면 이미지를 추가하면 ‘작품 vs 현실’ 비교 카드를 만들 수 있어요."),
  "detail.completedOn": ("%@ 达成巡礼", "%@ 達成巡禮", "%@ 巡礼達成", "Visited on %@", "%@ 순례 완료"),
  # 用户校准机位
  "calib.title": ("校准这个机位", "校準這個機位", "撮影位置を補正", "Calibrate this spot", "촬영 위치 보정"),
  "calib.entry": ("校准机位", "校準機位", "位置を補正", "Calibrate", "위치 보정"),
  "calib.sceneButton": ("校准机位", "校準機位", "位置を補正", "Calibrate", "위치 보정"),
  "calib.intro": ("请站到动画画面里的拍摄位置，把手机竖起来，让摄像头的朝向和画面一致，然后提交。你的数据会帮助后来的巡礼者更准确地对准名场面。",
                  "請站到動畫畫面裡的拍攝位置，把手機豎起來，讓相機的朝向和畫面一致，然後送出。你的資料會幫助後來的巡禮者更準確地對準名場面。",
                  "作中のカットが撮られた位置に立ち、スマホを立てて、カメラの向きを場面と同じにしてから送信してください。あなたのデータが、これから訪れる巡礼者の役に立ちます。",
                  "Stand where the scene was framed, hold your phone upright and point the camera the same way as the scene, then submit. Your data helps future visitors line up the shot.",
                  "작품 속 장면이 그려진 위치에 서서 휴대폰을 세우고 카메라 방향을 장면과 맞춘 뒤 제출해 주세요. 여러분의 데이터가 다음 순례자에게 도움이 돼요."),
  "calib.accuracy": ("位置精度 ±%ld 米", "位置精度 ±%ld 公尺", "位置精度 ±%ldm", "Location accuracy ±%ld m", "위치 정확도 ±%ldm"),
  "calib.heading": ("朝向 %@ %ld°（±%ld°）", "朝向 %@ %ld°（±%ld°）", "向き %@ %ld°（±%ld°）", "Facing %@ %ld° (±%ld°)", "방향 %@ %ld° (±%ld°)"),
  "calib.headingNone": ("指南针不可用", "指南針無法使用", "コンパスを利用できません", "Compass unavailable", "나침반을 사용할 수 없어요"),
  "calib.pitch": ("俯仰 %+ld°", "俯仰 %+ld°", "仰角 %+ld°", "Tilt %+ld°", "기울기 %+ld°"),
  "calib.distance": ("距现有机位 %@", "距現有機位 %@", "登録済みの位置から %@", "%@ from the listed spot", "등록된 위치에서 %@"),
  "calib.good": ("数据质量良好，可以提交", "資料品質良好，可以送出", "データは良好です。送信できます", "Good readings — ready to submit", "데이터 품질 양호: 제출할 수 있어요"),
  "calib.issue.gps": ("GPS 精度不足：请到空旷处稍等片刻", "GPS 精度不足：請到空曠處稍等片刻", "GPS の精度が足りません。開けた場所で少し待ってください",
                      "GPS is imprecise — wait a moment in an open area", "GPS 정확도가 낮아요. 탁 트인 곳에서 잠시 기다려 주세요"),
  "calib.issue.compass": ("指南针精度较低：请远离金属物体，或在空中画几次 ∞ 字", "指南針精度較低：請遠離金屬物體，或在空中畫幾次 ∞ 字",
                          "コンパスの精度が低いです。金属から離れるか、空中で ∞ を描いてください",
                          "Compass is imprecise — move away from metal or draw ∞ in the air", "나침반 정확도가 낮아요. 금속에서 떨어지거나 공중에 ∞를 그려 주세요"),
  "calib.issue.noHeading": ("无法获取朝向：请确认已允许定位权限", "無法取得朝向：請確認已允許定位權限", "向きを取得できません。位置情報の許可を確認してください",
                            "Can't read the direction — check that location access is allowed", "방향을 알 수 없어요. 위치 권한을 확인해 주세요"),
  "calib.issue.far": ("离现有机位较远。如果你确定这里才是正确的机位，请照常提交，并在备注里说明",
                      "離現有機位較遠。如果你確定這裡才是正確的機位，請照常送出，並在備註裡說明",
                      "登録済みの位置から離れています。ここが正しい撮影位置だと確信がある場合は、そのまま送信し、メモで教えてください",
                      "You're far from the listed spot. If you're sure this is the right place, submit anyway and say so in the note",
                      "등록된 위치와 멀리 떨어져 있어요. 여기가 맞다고 확신한다면 그대로 제출하고 메모에 남겨 주세요"),
  "calib.noteLabel": ("备注（可选）", "備註（選填）", "メモ（任意）", "Note (optional)", "메모(선택)"),
  "calib.notePlaceholder": ("例如：机位在台阶最上面一级，朝向车站方向", "例如：機位在階梯最上面一階，朝向車站方向",
                            "例：階段のいちばん上、駅の方向を向いて", "e.g. top step of the stairs, facing the station",
                            "예: 계단 맨 위 칸, 역 방향을 바라보며"),
  "calib.privacy": ("将提交：此刻的位置、朝向、俯仰角和备注。不包含你的姓名、联系方式或照片。数据保存在 Apple iCloud，仅用于改进圣地数据。",
                    "將送出：此刻的位置、朝向、俯仰角和備註。不包含你的姓名、聯絡方式或照片。資料保存在 Apple iCloud，僅用於改進聖地資料。",
                    "送信される内容：現在の位置・向き・仰角・メモ。名前や連絡先、写真は含まれません。データは Apple の iCloud に保存され、聖地データの改善にのみ使われます。",
                    "We'll send: your current location, direction, tilt and note — no name, contact details or photos. Data is stored in Apple iCloud and used only to improve spot data.",
                    "제출 내용: 현재 위치, 방향, 기울기, 메모. 이름·연락처·사진은 포함되지 않아요. 데이터는 Apple iCloud에 저장되며 성지 데이터 개선에만 사용돼요."),
  "calib.submit": ("提交校准", "送出校準", "補正を送信", "Submit calibration", "보정 제출"),
  "calib.thanks": ("感谢！你的校准已提交，会帮助大家更准确地对准名场面。", "感謝！你的校準已送出，會幫助大家更準確地對準名場面。",
                   "ありがとうございます！送信しました。みんながより正確に名シーンを再現できるようになります。",
                   "Thank you! Your calibration was submitted and will help everyone line up the scene.",
                   "감사합니다! 보정이 제출되어 모두가 명장면을 더 정확히 맞출 수 있게 돼요."),
  "calib.queued": ("现在连不上网络，已保存在手机上，联网后会自动提交。", "現在連不上網路，已保存在手機上，連網後會自動送出。",
                   "現在オフラインのため端末に保存しました。オンラインになると自動で送信します。",
                   "You're offline — saved on your phone and will be sent automatically later.",
                   "지금은 오프라인이라 휴대폰에 저장했어요. 연결되면 자동으로 제출돼요."),
  "calib.noAccount": ("需要登录 iCloud 才能提交。已保存在手机上，登录后会自动提交；你也可以复制数据发给我们。",
                      "需要登入 iCloud 才能送出。已保存在手機上，登入後會自動送出；你也可以複製資料傳給我們。",
                      "送信には iCloud へのサインインが必要です。端末に保存したので、サインイン後に自動で送信します。データをコピーして送っていただくこともできます。",
                      "Sign in to iCloud to submit. It's saved on your phone and will be sent after you sign in — or copy the data and send it to us.",
                      "제출하려면 iCloud 로그인이 필요해요. 휴대폰에 저장했으니 로그인 후 자동으로 제출돼요. 데이터를 복사해 보내 주셔도 돼요."),
  "calib.failed": ("提交失败：%@", "送出失敗：%@", "送信できませんでした：%@", "Couldn't submit: %@", "제출하지 못했어요: %@"),
  "calib.copy": ("复制数据", "複製資料", "データをコピー", "Copy data", "데이터 복사"),
  "calib.copied": ("已复制", "已複製", "コピーしました", "Copied", "복사했어요"),
  "category.anime": ("日漫", "動漫", "アニメ", "Anime", "애니"),
  "category.drama": ("日剧", "日劇", "ドラマ", "J-dramas", "일드"),
  "category.film": ("日影", "日片", "実写映画", "Movies", "일본 영화"),
  "format.workBadge": ("%@《%@》", "%@《%@》", "%@『%@』", "%@ · %@", "%@ 〈%@〉"),
  "detail.highlight": ("为什么是名场面", "為什麼是名場面", "ここが名シーン", "Why it's iconic", "명장면인 이유"),
  "detail.guide": ("巡礼攻略", "巡禮攻略", "巡礼ガイド", "Visiting guide", "순례 가이드"),
  "detail.access": ("怎么去", "怎麼去", "アクセス", "Getting there", "가는 방법"),
  "detail.bestTime": ("最佳到访时间", "最佳造訪時間", "おすすめの時間帯", "Best time to visit", "추천 방문 시기"),
  "detail.shot": ("机位", "機位", "撮影ポジション", "Camera angle", "촬영 구도"),
  "detail.shotLevel": ("面向%@，平视拍摄", "面向%@，平視拍攝", "%@向き・目線の高さで", "Face %@, camera level", "%@쪽을 향해 수평으로"),
  "detail.shotUp": ("面向%@，仰角约 %ld°", "面向%@，仰角約 %ld°", "%@向き・%ld°ほど見上げて", "Face %@, tilt up about %ld°", "%@쪽을 향해 약 %ld° 올려서"),
  "detail.shotDown": ("面向%@，俯角约 %ld°", "面向%@，俯角約 %ld°", "%@向き・%ld°ほど見下ろして", "Face %@, tilt down about %ld°", "%@쪽을 향해 약 %ld° 내려서"),
  "detail.revealSpoiler": ("含剧透，点击查看", "含劇透，點擊查看", "ネタバレを含みます。タップして表示", "Contains spoilers — tap to read", "스포일러 포함 · 탭해서 보기"),
  "detail.aboutWork": ("关于作品", "關於作品", "作品について", "About the title", "작품 정보"),
  "detail.officialSite": ("官方网站", "官方網站", "公式サイト", "Official site", "공식 사이트"),
  "detail.chooseMapApp": ("用哪个地图导航？", "用哪個地圖導航？", "どの地図アプリで開きますか？", "Open directions in", "어느 지도 앱으로 열까요?"),
  "detail.chooseMapAppHint": ("可以在设置里设为默认，下次直接打开", "可以在設定中設為預設，下次直接開啟", "設定でいつも使うアプリを選べます", "You can set a default in Settings", "설정에서 기본 앱을 정할 수 있어요"),
  "mapApp.google": ("Google 地图", "Google 地圖", "Google マップ", "Google Maps", "Google 지도"),
  "mapApp.apple": ("Apple 地图", "Apple 地圖", "Apple マップ", "Apple Maps", "Apple 지도"),
  "mapApp.amap": ("高德地图", "高德地圖", "高徳地図（Amap）", "Amap", "가오더 지도"),
  "mapApp.baidu": ("百度地图", "百度地圖", "百度地図", "Baidu Maps", "바이두 지도"),
  "mapApp.web": ("%@（网页版）", "%@（網頁版）", "%@（Web版）", "%@ (web)", "%@ (웹)"),
  "common.cancel": ("取消", "取消", "キャンセル", "Cancel", "취소"),
  "photo.realPlace": ("实景照片", "實景照片", "現地の写真", "Real location", "실제 장소"),
  "photo.credit": ("照片：%@ · %@", "照片：%@ · %@", "写真：%@ · %@", "Photo: %@ · %@", "사진: %@ · %@"),
  "settings.title": ("设置", "設定", "設定", "Settings", "설정"),
  "settings.language": ("语言", "語言", "言語", "Language", "언어"),
  "settings.followSystem": ("跟随系统", "跟隨系統", "システムに合わせる", "Use system language", "시스템 언어"),
  "settings.languageFooter": ("切换后立即生效，名场面介绍也会换成对应语言。", "切換後立即生效，名場面介紹也會換成對應語言。", "すぐに切り替わり、名シーンの解説もその言語で表示されます。", "Takes effect right away, including scene descriptions.", "바로 적용되며 명장면 설명도 해당 언어로 바뀌어요."),
  "settings.mapApp": ("导航地图", "導航地圖", "経路案内アプリ", "Directions app", "길찾기 앱"),
  "settings.askEveryTime": ("每次询问", "每次詢問", "毎回選ぶ", "Ask every time", "매번 묻기"),
  "settings.mapAppFooter": ("没有安装的地图会打开网页版。在日本，Google 地图的电车换乘信息最全。", "沒有安裝的地圖會開啟網頁版。在日本，Google 地圖的電車轉乘資訊最完整。", "インストールされていない地図アプリはWeb版で開きます。", "Apps that aren't installed open on the web. In Japan, Google Maps has the most complete train routes.", "설치되지 않은 앱은 웹으로 열려요. 일본에서는 Google 지도의 전철 환승 정보가 가장 자세해요."),
  "settings.data": ("名场面数据", "名場面資料", "名シーンのデータ", "Scene data", "명장면 데이터"),
  "settings.sceneCount": ("名场面", "名場面", "名シーン", "Scenes", "명장면"),
  "settings.workCount": ("作品", "作品", "作品", "Titles", "작품"),
  "settings.calibrationNote": ("机位坐标来自公开资料整理，可能有偏差。到了现场可以在名场面页点「校准机位」，把准确的位置和朝向提交给我们。", "機位座標整理自公開資料，可能有偏差。到了現場可以在名場面頁點「校準機位」，把準確的位置和朝向提交給我們。", "撮影位置は公開情報をもとにしているため、ずれている場合があります。現地で「位置を補正」から正しい位置と向きを送ってください。", "Spot positions are compiled from public sources and may be off. On site, tap “Calibrate” on a scene to send us the exact position and direction.", "촬영 위치는 공개 자료를 바탕으로 해 오차가 있을 수 있어요. 현장에서 ‘위치 보정’을 눌러 정확한 위치와 방향을 보내 주세요."),
  "settings.credits": ("版权与致谢", "版權與致謝", "著作権・クレジット", "Credits", "저작권 및 출처"),
  "settings.creditsBody": ("作品名称及相关权利归各自权利人所有，本 App 与各作品官方无关，也不收录作品画面。实景照片来自 Wikimedia Commons，作者与许可证标注在对应名场面页。部分坐标参考 © OpenStreetMap contributors。", "作品名稱及相關權利歸各自權利人所有，本 App 與各作品官方無關，也不收錄作品畫面。實景照片來自 Wikimedia Commons，作者與授權標示在對應名場面頁。部分座標參考 © OpenStreetMap contributors。", "作品名および関連する権利は各権利者に帰属します。本アプリは各作品の公式とは関係がなく、作品の画像も収録していません。現地の写真は Wikimedia Commons のもので、撮影者とライセンスは各名シーンのページに記載しています。一部の座標は © OpenStreetMap contributors を参考にしています。", "Titles and related rights belong to their respective owners. This app isn't affiliated with any of them and contains no footage or stills. Location photos come from Wikimedia Commons; authors and licenses are shown on each scene. Some coordinates reference © OpenStreetMap contributors.", "작품명과 관련 권리는 각 권리자에게 있으며, 이 앱은 각 작품의 공식 앱이 아니고 작품 이미지를 수록하지 않아요. 실제 장소 사진은 Wikimedia Commons에서 가져왔으며 작가와 라이선스는 각 명장면 페이지에 표시돼요. 일부 좌표는 © OpenStreetMap contributors를 참고했어요."),
  "settings.version": ("版本", "版本", "バージョン", "Version", "버전"),
  "detail.photographer": ("请人帮我拍", "請人幫我拍", "誰かに撮ってもらう", "Have someone take your photo", "다른 사람에게 찍어 달라기"),
  "pg.title": ("请人帮你拍", "請人幫你拍", "誰かに撮ってもらう", "Get someone to take your shot", "다른 사람에게 부탁하기"),
  "pg.subtitle": ("你来当主角，App 带着拍照的人对好构图", "你來當主角，App 帶著拍照的人對好構圖", "あなたが主人公。撮る人はアプリが構図までガイドします", "You play the lead — the app guides your photographer to the exact framing", "당신이 주인공. 찍는 사람은 앱이 구도까지 안내해요"),
  "pg.step1": ("你：站到主角的位置——机位前方约 %@ 米，面向镜头", "你：站到主角的位置——機位前方約 %@ 公尺，面向鏡頭", "あなた：主人公の位置へ。撮影位置の約 %@ m 先で、カメラの方を向いて", "You: stand where the lead stands — about %@ m in front of the camera, facing it", "당신: 주인공 자리로. 촬영 위치 앞 약 %@ m, 카메라를 바라보고"),
  "pg.step2": ("把手机交给帮你拍照的人", "把手機交給幫你拍照的人", "スマホを撮ってくれる人に渡す", "Hand your phone to your photographer", "휴대폰을 찍어 줄 사람에게 건네기"),
  "pg.step3": ("拍照的人跟着大箭头调整，对齐后自动倒数 3 秒拍照", "拍照的人跟著大箭頭調整，對齊後自動倒數 3 秒拍照", "撮る人は大きな矢印に従うだけ。そろうと 3 秒カウントで自動撮影", "Your photographer follows the big arrows; once lined up, it counts down 3 s and shoots", "찍는 사람은 큰 화살표만 따라가면 돼요. 맞춰지면 3초 후 자동 촬영"),
  "pg.markSubject": ("标记主角位置", "標記主角位置", "主人公の位置を指定", "Mark the lead's position", "주인공 위치 지정"),
  "pg.markHint": ("在你的名场面截图上框出主角，拍出来的构图会和原作一致", "在你的名場面截圖上框出主角，拍出來的構圖會和原作一致", "名シーン画像で主人公を囲むと、同じ構図で撮れます", "Box the lead on your scene screenshot to match the original framing", "명장면 이미지에서 주인공을 지정하면 원작과 같은 구도로 찍혀요"),
  "pg.defaultFraming": ("未标记时按全身居中构图", "未標記時以全身置中構圖", "未指定のときは全身・中央の構図になります", "Without a mark, it frames you full-body in the center", "지정하지 않으면 전신·가운데 구도로 찍어요"),
  "pg.guideLanguage": ("拍照人的指引语言", "拍照者的指引語言", "撮る人向けの案内の言語", "Photographer's language", "찍는 사람 안내 언어"),
  "pg.start": ("交给拍照的人，开始", "交給拍照的人，開始", "撮る人に渡して開始", "Hand over & start", "건네고 시작"),
  "pg.farFromSpot": ("离机位还有 %@，先一起走到机位附近", "離機位還有 %@，先一起走到機位附近", "撮影位置まであと %@。まず一緒に近くまで行きましょう", "You're %@ from the spot — walk there together first", "촬영 위치까지 %@ 남았어요. 먼저 함께 가까이 가세요"),
  "pg.autoShutter": ("自动拍", "自動拍", "自動撮影", "Auto", "자동 촬영"),
  "pg.voice": ("语音", "語音", "音声", "Voice", "음성"),
  "pg.ghost": ("叠图", "疊圖", "重ねる", "Overlay", "겹쳐 보기"),
  "pg.saved": ("已按原作构图保存到相册", "已按原作構圖儲存到相簿", "原作の構図で写真に保存しました", "Saved to Photos, framed like the original", "원작 구도로 사진에 저장했어요"),
  "pg.retake": ("再拍一张", "再拍一張", "もう一枚", "Retake", "다시 찍기"),
  "pg.editorTitle": ("标记主角位置", "標記主角位置", "主人公の位置", "Mark the lead", "주인공 위치"),
  "pg.editorHint": ("拖动人形框到主角站的位置，拖动上方圆点调整大小", "拖動人形框到主角站的位置，拖動上方圓點調整大小", "人型の枠を主人公の位置へ。上の丸をドラッグして大きさを調整", "Drag the figure onto the lead; drag the top handle to resize", "인형 틀을 주인공 위치로 옮기고, 위쪽 점으로 크기를 조절하세요"),
  "pg.reset": ("重置", "重置", "リセット", "Reset", "초기화"),
  "pg.addScreenshot": ("先添加名场面截图", "先新增名場面截圖", "名シーン画像を追加", "Add a scene screenshot first", "명장면 이미지를 먼저 추가"),
  "pg.find": ("让被拍的人进入画面", "讓被拍的人進入畫面", "撮られる人を画面に入れて", "Get the person into the frame", "찍을 사람을 화면 안에 넣어 주세요"),
  "pg.turnLeft": ("向左转 %ld°", "向左轉 %ld°", "左に %ld° 向けて", "Turn left %ld°", "왼쪽으로 %ld° 돌려요"),
  "pg.turnRight": ("向右转 %ld°", "向右轉 %ld°", "右に %ld° 向けて", "Turn right %ld°", "오른쪽으로 %ld° 돌려요"),
  "pg.tiltUp": ("镜头往上抬 %ld°", "鏡頭往上抬 %ld°", "%ld° 上に傾けて", "Tilt up %ld°", "%ld° 위로 기울여요"),
  "pg.tiltDown": ("镜头往下压 %ld°", "鏡頭往下壓 %ld°", "%ld° 下に傾けて", "Tilt down %ld°", "%ld° 아래로 기울여요"),
  "pg.closer": ("往前走 %@ 米", "往前走 %@ 公尺", "%@ m 前へ", "Walk %@ m closer", "%@ m 앞으로"),
  "pg.back": ("往后退 %@ 米", "往後退 %@ 公尺", "%@ m 下がって", "Step back %@ m", "%@ m 뒤로"),
  "pg.stepLeft": ("往左走 %@ 米", "往左走 %@ 公尺", "左へ %@ m", "Move %@ m left", "왼쪽으로 %@ m"),
  "pg.stepRight": ("往右走 %@ 米", "往右走 %@ 公尺", "右へ %@ m", "Move %@ m right", "오른쪽으로 %@ m"),
  "pg.raise": ("手机举高一点", "手機舉高一點", "スマホを少し高く", "Raise the phone a little", "휴대폰을 조금 높이"),
  "pg.lower": ("手机放低一点", "手機放低一點", "スマホを少し低く", "Lower the phone a little", "휴대폰을 조금 낮게"),
  "pg.perfect": ("完美！保持不动", "完美！保持不動", "バッチリ！そのまま", "Perfect! Hold still", "완벽해요! 그대로"),
  "pg.goto": ("先走到机位：%@，%@方向", "先走到機位：%@，%@方向", "まず撮影位置へ：%@・%@の方向", "Walk to the spot first: %@ to the %@", "먼저 촬영 위치로: %@, %@쪽"),
  "pg.photographerHeader": ("请帮忙拍一张名场面", "請幫忙拍一張名場面", "名シーンの写真をお願いします", "Please help take this scene photo", "명장면 사진 한 장 부탁해요"),
}

# Info.plist（权限说明、App 名称）
INFO = {
  "CFBundleDisplayName": ("圣地巡礼", "聖地巡禮", "聖地巡礼", "Seichi Junrei", "성지순례"),
  "NSLocationWhenInUseUsageDescription": (
    "用于发现你附近的动画圣地，并判断你是否已经站在名场面的机位上。",
    "用於發現你附近的動畫聖地，並判斷你是否已經站在名場面的機位上。",
    "近くの聖地を見つけ、名シーンの撮影位置に立っているかを判定するために使用します。",
    "Used to find pilgrimage spots near you and to tell when you're standing at a scene's spot.",
    "근처의 성지를 찾고, 명장면 촬영 위치에 서 있는지 판단하는 데 사용해요."),
  "NSLocationAlwaysAndWhenInUseUsageDescription": (
    "开启后，当你靠近动画圣地时会收到提醒，即使 App 没有打开。",
    "開啟後，當你靠近動畫聖地時會收到提醒，即使 App 沒有打開。",
    "許可すると、アプリを開いていなくても聖地に近づいたときに通知します。",
    "Lets the app alert you when you're near a pilgrimage spot, even when it isn't open.",
    "허용하면 앱을 열지 않아도 성지 근처에 가면 알려 드려요."),
  "NSCameraUsageDescription": (
    "在名场面机位上通过相机取景，帮你对准动画中的同一个画面。",
    "在名場面機位上透過相機取景，幫你對準動畫中的同一個畫面。",
    "撮影位置でカメラを使い、作中と同じ構図に合わせるために使用します。",
    "Used at a scene's spot to line up the camera with the same shot as in the story.",
    "명장면 촬영 위치에서 카메라로 작품 속과 같은 구도를 맞추는 데 사용해요."),
  "NSMotionUsageDescription": (
    "通过陀螺仪和指南针判断你面朝的方向，引导你转向名场面的视角。",
    "透過陀螺儀和指南針判斷你面朝的方向，引導你轉向名場面的視角。",
    "ジャイロとコンパスで向いている方向を判定し、名シーンの視点へ案内します。",
    "Uses the gyroscope and compass to tell which way you're facing and guide you to the scene's view.",
    "자이로와 나침반으로 바라보는 방향을 파악해 명장면의 시점으로 안내해요."),
  "NSPhotoLibraryAddUsageDescription": (
    "把你在圣地拍下的“名场面重现”照片保存到相册。",
    "把你在聖地拍下的「名場面重現」照片儲存到相簿。",
    "聖地で撮った「名シーン再現」写真を写真ライブラリに保存します。",
    "Saves the photos you take at pilgrimage spots to your library.",
    "성지에서 찍은 ‘명장면 재현’ 사진을 사진 보관함에 저장해요."),
}

HEADER = "/* 由 tools/l10n.py 生成，请勿手动修改 */\n"

def render(table, i):
    lines = [HEADER]
    for k, vals in table.items():
        lines.append('"%s" = "%s";\n' % (k, vals[i].replace('"', '\\"')))
    return "".join(lines)

def outputs():
    out = {}
    for i, lang in enumerate(LANGS):
        d = os.path.join(RES, f"{lang}.lproj")
        out[os.path.join(d, "Localizable.strings")] = render(S, i)
        out[os.path.join(d, "InfoPlist.strings")] = render(INFO, i)
    return out

SPEC = re.compile(r"%(?:\d+\$)?[@dlfs]+")

def check():
    errors = []
    for table in (S, INFO):
        for k, vals in table.items():
            if len(vals) != len(LANGS):
                errors.append(f"{k}: expected {len(LANGS)} translations, got {len(vals)}")
                continue
            base = sorted(SPEC.findall(vals[0]))
            for lang, v in zip(LANGS, vals):
                if not v.strip():
                    errors.append(f"{k} [{lang}]: empty")
                if sorted(SPEC.findall(v)) != base:
                    errors.append(f"{k} [{lang}]: placeholders {SPEC.findall(v)} != {base}")
    used = set()
    for f in glob.glob(os.path.join(ROOT, "SeichiJunrei", "**", "*.swift"), recursive=True):
        src = open(f, encoding="utf-8").read()
        used |= set(re.findall(r'\bL(?:In\([^,()]+,\s*|\()"([A-Za-z0-9_.]+)"', src))
    used = {u for u in used if not u.endswith(".")}
    for k in sorted(used - set(S)):
        errors.append(f"key used in code but missing from table: {k}")
    for path, content in outputs().items():
        if not os.path.exists(path) or open(path, encoding="utf-8").read() != content:
            errors.append(f"generated file out of date: {os.path.relpath(path, ROOT)} (run: python3 tools/l10n.py generate)")
    unused = sorted(set(S) - used - {f"compass.{i}" for i in range(8)})
    if unused:
        print("note: keys not referenced by a literal L(\"…\") call:", ", ".join(unused))
    if errors:
        print("\n".join(errors)); sys.exit(1)
    print(f"l10n OK: {len(S)} UI keys + {len(INFO)} Info.plist keys × {len(LANGS)} languages")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "generate":
        for path, content in outputs().items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8").write(content)
        print("generated", len(outputs()), "files")
    else:
        check()
