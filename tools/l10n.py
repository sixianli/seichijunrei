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
  "media.anime": ("动画", "動畫", "アニメ", "Anime", "애니메이션"),
  "media.animeFilm": ("动画电影", "動畫電影", "アニメ映画", "Anime film", "애니 영화"),
  "media.film": ("电影", "電影", "映画", "Film", "영화"),
  "media.drama": ("电视剧", "電視劇", "ドラマ", "TV drama", "드라마"),
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
  "map.searchPrompt": ("搜索动画、电影、电视剧的名字", "搜尋動畫、電影、電視劇的名稱", "アニメ・映画・ドラマのタイトルで検索",
                       "Search anime, films, TV dramas", "애니메이션·영화·드라마 제목 검색"),
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
  "list.searchPrompt": ("动画 / 电影 / 电视剧名称", "動畫 / 電影 / 電視劇名稱", "アニメ・映画・ドラマ名",
                        "Anime / film / drama title", "애니메이션 / 영화 / 드라마 제목"),
  # 名场面模式
  "scene.calibrating": ("正在校准方向…\\n请把手机竖起，在空中画几次 ∞ 字", "正在校準方向…\\n請把手機豎起，在空中畫幾次 ∞ 字",
                        "方位を調整中…\\nスマホを立てて、空中で ∞ を何回か描いてください",
                        "Calibrating direction…\\nHold your phone upright and draw ∞ in the air a few times",
                        "방향을 보정하는 중…\\n휴대폰을 세우고 공중에 ∞ 모양을 몇 번 그려 주세요"),
  "scene.story": ("剧情", "劇情", "ストーリー", "Story", "줄거리"),
  "scene.recordSpot": ("记录机位", "記錄機位", "撮影位置を記録", "Record spot", "촬영 위치 기록"),
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
  "detail.enterScene": ("进入名场面！", "進入名場面！", "名シーンに入る！", "Enter the scene!", "명장면 속으로!"),
  "detail.startGuide": ("开启方向指引", "開啟方向指引", "方向ガイドを開始", "Start direction guide", "방향 안내 시작"),
  "detail.story": ("剧情背景", "劇情背景", "ストーリー", "Story", "줄거리"),
  "detail.tips": ("巡礼小贴士", "巡禮小提醒", "巡礼のヒント", "Pilgrimage tips", "성지순례 팁"),
  "detail.openMaps": ("在地图 App 中导航", "在地圖 App 中導航", "マップで経路を表示", "Directions in Maps", "지도 앱에서 길 안내"),
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
        used |= set(re.findall(r'\bL\("([A-Za-z0-9_.]+)"', src))
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
