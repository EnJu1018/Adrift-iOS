# Web / iOS 同步盤點

基準：2026-09-10 的 repository 實作。盤點代表程式碼能力，不代表已登入正式環境驗收。

| 項目 | Web 已完成 | iOS 修改前 | 需要修改的檔案 |
| --- | --- | --- | --- |
| 使用者 | 註冊、登入、個人資料、頭像、名稱、email、密碼、刪除帳號 | Keychain JWT、登入、註冊、頭像；其餘設定缺少 | AuthService、AuthViewModel、UserService、SettingsView、ProfileView |
| 日記 | 地圖、建立、詳情、限時限地編輯、刪除 | 真 API 地圖和建立；詳情只有快照 | DiaryService、Diary、MapDiaryViewModel、DiaryDetailView |
| 圖片 | image multipart、相對 URL | 已上傳、AsyncImage placeholder；頭像可能傳 HEIC | APIConfig、AddDiaryView、SettingsView |
| 社交 | 搜尋、邀請、接受、拒絕、收回、移除、好友資料、推薦 | 搜尋、邀請、接受、拒絕、列表 | FriendService、FriendsViewModel、FriendsView |
| 探索 | 依位置查詢公開日記 | 缺少 | ExploreView、DiaryService、AppRefreshManager |
| 同步 | 日記事件、操作後同步 | 前景輪詢、節流；缺少跨畫面操作同步 | MainTabView、AppRefreshManager、MapDiaryViewModel |
| 其他 | 共鳴、歷年今日、AI、管理後台 | AI；其餘缺少 | 不屬本次核心八頁範圍，另列後續進度 |

## 真實 API 契約

- 架構：Web / SwiftUI → 同一 Express API → MongoDB Atlas。iOS 無資料庫連線。
- routes：auth、users、diaries、friends、location、ai、admin。控制器直接寫在 routes；models 為 User、Diary，邀請內嵌在 User。
- 回應包裝：`{ success, message, data }`。登入／註冊的 data 為 `{ token, user }`，同時提供頂層 token/user。
- JWT：Authorization Bearer；有效期 7 天；沒有 refresh-token API。iOS 將 JWT 存 Keychain。
- User：`_id`（本人另有 id）、name、email（僅本人）、userCode、avatar、role、createdAt。
- Diary：`_id`、title、text（探索另有 content）、mood `{type,intensity}`、visibility、imageUrl、user（populate 作者）、createdAt。
- 座標：新增傳 lat/lng；讀取為 GeoJSON `location.coordinates: [longitude, latitude]`，探索另有 location.lat/lng。不是頂層 latitude/longitude 的假定 schema。
- 心情：calm、joy、sad、wonder、anxious、confused、nostalgic、other。iOS 原先把生氣存為焦慮、懷舊讀成平靜，需修正。
- 日記列表 `GET /diaries` 回傳 data.diaries；詳情／建立／編輯回傳 data.diary；探索 `GET /diaries/explore?lat=&lng=&radius=` 回傳 data 陣列。
- 編輯 `PATCH /diaries/:id` 使用 JSON title/content/moodType/moodIntensity/visibility/currentLocation `{lat,lng,accuracyType}`。後端限制本人、發布一小時內、原地一公里內；不允許更改原始位置、圖片、時間。
- 圖片：新增使用 multipart image，上限 5 MiB，JPG/PNG/WebP；頭像 PATCH multipart avatar，上限 10 MiB。相對 /uploads 路徑接 API base URL，與 Web getImageUrl 相同。
- 好友：`GET /friends`、`GET /friends/requests`、`GET /friends/requests/sent`；邀請識別欄位 requestId，收件 from、寄件 to。
- 好友操作：POST /friends/request `{targetUserId}`；POST /friends/requests/:id/accept 或 reject；DELETE /friends/requests/:id/cancel；DELETE /friends/:id。
- 可見性由後端 diaryQueryForViewer 判定：自己的全部、其他人的 public、好友的 friends；iOS 僅篩選後端已授權回傳的資料。
- 列表上限目前為 200，沿用 Web；不代表帳號所有歷史日記。完整歷史分頁需另行擴充既有 API。

## 驗收邊界

需以兩個實際測試帳號驗證跨平台建立／修改／刪除、圖片、邀請及 public/friends/private 權限。未提供帳號時不擅自在正式環境建立資料，也不以假資料取代 App API。

## 本次完成（2026-09-11）

- 日記詳情改用 GET /diaries/:id 驗證權限；補原生編輯與刪除確認。編輯帶最新位置、保留原圖與原始座標，遵守後端 canEdit／時間／距離限制。
- 新增 ExploreView 呼叫探索 API；ProfileView 與好友日記頁使用後端已授權的日記列表。保留原有 MapKit 與 AI 洞察。
- 好友補收回、移除，操作成功即同步本地狀態，再重新抓取 API；搜尋結果的好友狀態也自動更新。
- 設定補名稱、電子郵件、密碼、移除頭像；照片統一轉 JPEG，並檢查後端大小限制。
- 所有八種心情值能正確往返；中文城市／地區名共用解析與快取，畫面不顯示原始經緯度。
- 保留 Web 的 /api/uploads 拼接規則，支援相對／絕對路徑並防止重複 /api；延用圖片載入／失敗 placeholder。
- 註冊直接使用後端簽發的 JWT；暫時斷線不刪除 Keychain token，有既存使用者快取時維持登入畫面狀態；後端明確回報 token 失效才登出。錯誤的帳號設定密碼不視為 token 失效。
- 前景每 30 秒自動輪詢，回到前景／進頁面亦節流更新。操作後刷新會排入進行中的請求之後；過期請求不覆蓋新的日記或好友狀態。這不是即時推播，跨裝置變更通常在下一次成功輪詢顯示。
- 未修改 Web、Express routes 或 MongoDB schema；iOS 無 MongoDB URI、連線或 WebView。

## 已執行檢查

- Xcode Simulator build（arm64／x86_64）：通過。
- iPhone 17e／iOS 26.5 模擬器：安裝、啟動、中文登入畫面顯示正常；尚未登入驗證新功能畫面。
- `bash Tests/run-contract-checks.sh`：通過。涵蓋真實 services 的登入／註冊、Keychain、Bearer、日記 CRUD、探索陣列與 GeoJSON、multipart、好友操作、個人設定、中文錯誤、八種心情、圖片 URL，以及刷新節流／去重／操作後排程。
- 契約測試使用獨立 URLProtocol 回應，沒有呼叫正式 MongoDB；不能取代部署環境驗收。

## 實際帳號驗收清單（待執行）

1. A 在 Web 新增附圖公開日記，確認 iOS 在前景自動出現 pin、名稱、頭像、中文地點與圖片。
2. A 在 iOS 新增附圖日記，確認 Web 顯示同一 ID、心情、可見性與座標。
3. 在發布一小時內、原地一公里內編輯；另一平台自動反映。超時／超距編輯必須由後端拒絕。
4. 刪除日記後檢查兩端列表、pin、詳情；不得殘留可操作的舊內容。
5. A 邀請 B，B 接受／拒絕；A 收回邀請、移除好友；兩端狀態一致。
6. A、B 是好友時可見 friends；移除後不可見；私人日記只能作者看見。直接查詳情也必須受後端保護。
7. 名稱、電子郵件與頭像雙向修改；頭像 HEIC 照片可轉 JPEG 上傳，網頁也能顯示。
8. 重啟 App 自動登入；斷網啟動不清除 token；恢復網路後自動同步；token 過期回到登入頁。

後續差距：共鳴、歷年今日、推薦好友、帳號刪除、管理後台與頭像裁切尚未同步；本次不宣稱整個 Web 所有功能完全一致。
