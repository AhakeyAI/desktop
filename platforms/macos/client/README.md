# macOS Client

褰撳墠鏂囨。鐢ㄤ簬璇存槑 `platforms/macos/client/` 鐨?macOS 瀹㈡埛绔瀯寤轰笌鎵撳寘鍏ュ彛銆?
褰撳墠浠撳簱涓殑 macOS 閮ㄥ垎浠嶅浜?baseline 杩佸叆鍚庣殑鏁寸悊闃舵锛屽洜姝ゆ湰鏂囨。鍙褰曞綋鍓嶅彲鍒ゆ柇鐨勬瀯寤鸿矾寰勩€佹墦鍖呭叆鍙ｅ拰鍙戝竷闄愬埗锛屼笉鎶婄幇鐘舵弿杩颁负宸茬粡瀹屽叏鏍囧噯鍖栫殑鍙戝竷娴佺▼銆?
## 褰撳墠鐘舵€?
- macOS 瀹㈡埛绔簮鐮佸綋鍓嶄綅浜?`platforms/macos/client/`
- 褰撳墠宸ョ▼浠?Swift Package 涓哄叆鍙ｏ紝鍖呭惈涓や釜鍙墽琛岀洰鏍囷細
  - `AhaKeyConfig`
  - `ahakeyconfig-agent`
- 褰撳墠鑴氭湰宸茬粡瑕嗙洊鏈湴鏋勫缓銆佸畨瑁呫€丏MG 鎵撳寘涓庢寮忓垎鍙戞墦鍖呭叆鍙?- 褰撳墠鍙戝竷閾捐矾浠嶄緷璧栨湰鏈鸿瘉涔︺€乲eychain 涓?Apple 宸ュ叿閾鹃厤缃?
## 鍓嶇疆鏉′欢

褰撳墠鍙垽鏂殑鐜瑕佹眰濡備笅锛?
- macOS 15.0+
- Xcode 15+ 鎴栫瓑鏁堢殑 Swift 5.9+ toolchain
- Apple Silicon (`arm64`)
- `zsh`

褰撳墠鑴氭湰渚濊禆鐨勬湰鏈哄伐鍏峰涓嬶細

- 鏈湴鏋勫缓锛?  - `swift`
  - `iconutil`
  - `codesign`
  - `security`
  - `xattr`
  - `ditto`
- DMG 鎵撳寘锛?  - `hdiutil`
  - `osascript`
  - `spctl`
- 姝ｅ紡鍙戝竷鎵撳寘锛?  - `xcrun notarytool`
  - `xcrun stapler`

浠ヤ笅宸ュ叿鍙湪閮ㄥ垎鏈湴寮€鍙戣剼鏈腑浣跨敤锛?
- `openssl`
  - `scripts/ensure-dev-signing.sh` 鍦ㄥ垱寤烘湰鍦板紑鍙戣瘉涔︽椂浼氫娇鐢?- `rsync`
  - `scripts/build-debug.sh` 浼樺厛浣跨敤 `rsync`锛岀己澶辨椂浼氬洖閫€鍒版櫘閫氬鍒堕€昏緫

## 鐩綍缁撴瀯

```text
platforms/macos/client/
|-- Package.swift
|-- Makefile
|-- README.md
|-- Resources/
|   `-- DefaultOLED/
|-- scripts/
`-- Sources/
```

## 鏋勫缓鍏ュ彛

### 1. 鐩存帴浣跨敤 SwiftPM

```bash
swift build -c release --arch arm64 --product AhaKeyConfig
swift build -c release --arch arm64 --product ahakeyconfig-agent
```

褰撳墠鍛戒护浼氬垎鍒瀯寤轰富绋嬪簭涓?agent 鍙墽琛屾枃浠讹紝閫傚悎闇€瑕佺洿鎺ヨ瀵?SwiftPM 杈撳嚭鐨勫満鏅€?
### 2. 浣跨敤鏋勫缓鑴氭湰

```bash
bash scripts/build.sh
```

杩欐槸褰撳墠鏈€瀹屾暣鐨勬湰鍦版瀯寤哄叆鍙ｃ€傝剼鏈綋鍓嶄細锛?
- 浠?release 妯″紡鏋勫缓涓や釜鍙墽琛岀洰鏍?- 缁勮 `dist/AhaKey Studio.app`
- 鐢熸垚 `.icns` 鍥炬爣璧勬簮
- 鍐欏叆 `Info.plist`
- 鍐欏叆钃濈墮 entitlements
- 瀵?app 涓庡彲鎵ц鏂囦欢鎵ц绛惧悕
- 楠岃瘉绛惧悕缁撴灉

褰撳墠鍙杈撳嚭涓猴細

- `dist/AhaKey Studio.app`

褰撳墠鑴氭湰鏀寔浠ヤ笅甯哥敤鐜鍙橀噺锛?
- `APP_BUNDLE_NAME`
- `APP_DISPLAY_NAME`
- `OUTPUT_DIR`
- `ICON_SOURCE`
- `INSTALL_TO_APPLICATIONS`
- `INSTALL_DIR`
- `LAUNCH_AFTER_INSTALL`
- `SIGNING_IDENTITY`
- `REQUIRE_DEVELOPER_ID`

### 3. 浣跨敤 Makefile

```bash
make build
make install
```

褰撳墠 Makefile 鍙槸瀵硅剼鏈叆鍙ｅ仛钖勫寘瑁咃細

- `make build`
  - 绛変环浜?`./scripts/build.sh`
- `make install`
  - 绛変环浜庤缃?`INSTALL_TO_APPLICATIONS=1 LAUNCH_AFTER_INSTALL=1` 鍚庢墽琛?`./scripts/build.sh`

## 褰撳墠鍙垽鏂殑鏈湴鏋勫缓娴佺▼

濡傛棤鐗规畩闇€姹傦紝褰撳墠寤鸿鎸変互涓嬮『搴忔墽琛岋細

1. 杩愯 `make build` 鎴?`bash scripts/build.sh`
2. 纭鐢熸垚 `dist/AhaKey Studio.app`
3. 濡傞渶瀹夎鍒版湰鏈哄簲鐢ㄧ洰褰曪紝杩愯 `make install`

褰撳墠 `build.sh` 鐨勭鍚嶇瓥鐣ュ涓嬶細

- 浼樺厛浣跨敤 `Developer ID Application`
- 鑻ユ湭鎵惧埌涓旀湭寮哄埗瑕佹眰 Developer ID锛屽垯鍥為€€鍒?`Apple Development`
- 鑻ヤ粛鏈壘鍒帮紝鍒欏洖閫€鍒?ad-hoc 绛惧悕锛屼粎閫傜敤浜庢湰鍦版祴璇?
鍥犳锛屾湰鍦版瀯寤烘垚鍔熶笉绛変簬宸茬粡寰楀埌鍙寮忓垎鍙戠殑瀹夎鍖呫€?
## 璋冭瘯涓庢湰鍦版潈闄愯鏄?
褰撳墠浠撳簱杩樹繚鐣欎簡闈㈠悜鏈湴寮€鍙戠殑璋冭瘯鑴氭湰锛?
```bash
bash scripts/build-debug.sh
bash scripts/ensure-dev-signing.sh
bash scripts/fix-debug-permissions.sh
```

杩欎簺鑴氭湰褰撳墠涓昏鐢ㄤ簬锛?
- 鐢熸垚璋冭瘯妯″紡涓嬬殑 `.app`
- 灏介噺淇濇寔鏈湴璋冭瘯鏃剁殑 bundle identity / signing 绋冲畾
- 鍑忓皯閲嶅鎺堜簣 macOS TCC 鏉冮檺鐨勬儏鍐?- 鍦ㄦ湰鍦版潈闄愮姸鎬佸紓甯告椂閲嶆柊绛惧悕骞堕噸缃浉鍏虫潈闄?
褰撳墠杩欎簺鑴氭湰鍙簲瑙嗕负鏈湴寮€鍙戣緟鍔╁伐鍏凤紝涓嶅簲瑙嗕负姝ｅ紡鍙戝竷閾捐矾鐨勪竴閮ㄥ垎銆?
## DMG 鎵撳寘鍏ュ彛

### 鏈湴 / 娴嬭瘯鎵撳寘

```bash
bash scripts/package_dmg.sh
```

褰撳墠鑴氭湰浼氬厛鎵ц `build.sh`锛岀劧鍚庣户缁畬鎴愶細

- 鍑嗗 `.app` 涓?`/Applications` 蹇嵎鏂瑰紡鐨?staging 鐩綍
- 鐢熸垚 DMG 鑳屾櫙鍥?- 鍒涘缓鍙啓 DMG
- 閫氳繃 Finder 鑷姩鍖栬缃嫋鎷藉畨瑁呭竷灞€
- 杞崲涓哄帇缂?DMG
- 鍦ㄥ瓨鍦?`Developer ID Application` 鏃跺 DMG 绛惧悕
- 鍦ㄦ彁渚?`NOTARY_PROFILE` 鏃舵墽琛?notarization 涓?stapling
- 鏈€鍚庢墽琛?DMG 鏍￠獙

褰撳墠鍙杈撳嚭涓猴細

- `dist/AhaKey-Studio-macOS.dmg`

## 姝ｅ紡鍙戝竷鎵撳寘鍏ュ彛

```bash
bash scripts/release_dmg.sh
```

杩欐槸褰撳墠姝ｅ紡鍒嗗彂鍏ュ彛銆傚綋鍓嶈剼鏈細鏄惧紡瑕佹眰锛?
- 鍙敤鐨?`Developer ID Application` 璇佷功
- 鍙敤鐨?`notarytool` keychain profile

褰撳墠榛樿鐨?notary profile 鍚嶇О涓猴細

- `AhaKeyNotary`

鑻ョ己灏戜笂杩版潯浠讹紝鑴氭湰浼氱洿鎺ュけ璐ワ紝杩欐槸褰撳墠娴佺▼涓殑棰勬湡淇濇姢琛屼负锛岃€屼笉鏄厹搴曞洖閫€銆?
## 褰撳墠宸茬煡闄愬埗

- 褰撳墠鑴氭湰鏄庣‘鎸?`arm64` 鏋勫缓锛屾湰鏂囨。涓嶆妸 Intel / universal build 瑙嗕负宸叉敮鎸佽矾寰?- 褰撳墠姝ｅ紡鍙戝竷渚濊禆鏈満 keychain 涓殑璇佷功涓?notarization 閰嶇疆锛屼笉鏄紑绠卞嵆鐢ㄧ殑閫氱敤璐＄尞鑰呮祦绋?- 褰撳墠 ad-hoc 绛惧悕浠呴€傜敤浜庢湰鍦版祴璇曪紝涓嶇瓑鍚屼簬 Apple 棰佸彂璇佷功涓嬬殑姝ｅ紡鍒嗗彂淇′换
- 褰撳墠 notarization 涓嶆槸鑷姩鍙敤鑳藉姏锛屽繀椤绘樉寮忔彁渚?`NOTARY_PROFILE`
- 褰撳墠浠撳簱涓嶆彁浜?`.app`銆乣.dmg` 绛夋瀯寤轰骇鐗╋紱瀹夎鍖呭垎鍙戝簲閫氳繃 GitHub Releases
- 褰撳墠鍥炬爣婧愭枃浠?`VibeCodeKeyboard.ico` 鍦ㄩ儴鍒嗕粨搴撶姸鎬佷笅鍙兘涓嶅瓨鍦紝鑴氭湰浼氬洖閫€鍒伴粯璁ゅ浘鏍囩敓鎴愯矾寰?- 褰撳墠鏁翠綋娴佺▼浠嶅浜?baseline 鏁寸悊闃舵锛屽悗缁粛鍙兘缁х画缁熶竴鏋勫缓涓庡彂甯冪粏鑺?
## 浠撳簱涓笉鍖呭惈鐨勫唴瀹?
褰撳墠浠撳簱鍐呬笉搴旀彁浜や互涓嬪唴瀹癸細

- `.app`
- `.dmg`
- 鏈湴绛惧悕璇佷功
- 绉侀挜
- 鍏朵粬鏁忔劅鍙戝竷鏉愭枡

## 鐩稿叧鏂囨。

- [`../../../docs/installation.md`](../../../docs/installation.md)
- [`../../../docs/releases.md`](../../../docs/releases.md)
- [`../README.md`](../README.md)
