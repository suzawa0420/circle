Event.seed(:id,

# matching => Match 1:連携/2:複数連携/0:非掲載
# place => Place 1:連携/0:非連携
# { :id => 99, :category_id => 9, :order => "9999", :name => "99" , :ruby => "99",  :matching => 0, :place => 0, :openchat => "", :txt => "99" },

# Max activity id 64 (99 is その他)

  # 球技スポーツ
  { :id => 2, :category_id => 1, :order => "0101", :name => "バスケ" , :ruby => "basketball", :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/28860kzjimldNe2P9MOsqg", :txt => "バスケサークル・チーム" },
  { :id => 4, :category_id => 1, :order => "0102", :name => "バレーボール" , :ruby => "volleyball",  :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/J2oirsmlRsHc1QVS4sFb6Q", :txt => "バレーサークル・チーム" },
  { :id => 8, :category_id => 1, :order => "0103", :name => "フットサル" , :ruby => "futsal",  :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/jq0AbQjRV3XsyDnmvNidtA", :txt => "フットサルサークル・チーム" },
  { :id => 7, :category_id => 1, :order => "0104", :name => "草野球" , :ruby => "baseball",  :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/StLPRlAGJPjl9rHX9BTXug", :txt => "草野球チーム・サークル" },
  { :id => 22, :category_id => 1, :order => "0105", :name => "ソフトボール" , :ruby => "softball",  :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/StLPRlAGJPjl9rHX9BTXug", :txt => "ソフトボールチーム・サークル" },
  { :id => 16, :category_id => 1, :order => "0106", :name => "サッカー" , :ruby => "soccer",  :matching => 1, :place => 1, :openchat => "", :txt => "サッカーチーム・サークル" },
  { :id => 25, :category_id => 1, :order => "0107", :name => "ハンドボール" , :ruby => "handball",  :matching => 1, :place => 1, :openchat => "", :txt => "ハンドボールサークル・チーム" },
  { :id => 23, :category_id => 1, :order => "0108", :name => "ドッジボール" , :ruby => "dodgeball",  :matching => 0, :place => 0, :openchat => "", :txt => "ドッジボールサークル" },
  { :id => 43, :category_id => 1, :order => "0109", :name => "ラグビー" , :ruby => "rugby",  :matching => 0, :place => 0, :openchat => "", :txt => "ラグビーチーム・サークル" },
  { :id => 49, :category_id => 1, :order => "0110", :name => "アメフト" , :ruby => "american-football",  :matching => 0, :place => 0, :openchat => "", :txt => "アメフトチーム・サークル" },


  # ラケットスポーツ
  { :id => 5, :category_id => 2, :order => "0201", :name => "バドミントン" , :ruby => "badminton",  :matching => 1, :place => 1, :openchat => "https://line.me/ti/g2/9hLTdMzYeuiuO1fRinT_wQ", :txt => "バドミントンサークル・クラブ" },
  { :id => 9, :category_id => 2, :order => "0202", :name => "テニス" , :ruby => "tennis",  :matching => 1, :place => 1, :openchat => "", :txt => "テニスサークル" },
  { :id => 10, :category_id => 2, :order => "0203", :name => "卓球" , :ruby => "table-tennis",  :matching => 1, :place => 1, :openchat => "", :txt => "卓球サークル・クラブ" },
  { :id => 47, :category_id => 2, :order => "0204", :name => "パデル" , :ruby => "padel",  :matching => 0, :place => 0, :openchat => "", :txt => "パデルサークル" },
  { :id => 53, :category_id => 2, :order => "0205", :name => "ラクロス" , :ruby => "lacrosse",  :matching => 0, :place => 0, :openchat => "", :txt => "ラクロスサークル" },


  # その他のスポーツ
  { :id => 3, :category_id => 3, :order => "0301", :name => "ランニング" , :ruby => "running",  :matching => 0, :place => 0, :openchat => "", :txt => "ランニング・マラソンサークル" },
  { :id => 21, :category_id => 3, :order => "0302", :name => "ボルダリング" , :ruby => "bouldering",  :matching => 0, :place => 0, :openchat => "", :txt => "ボルダリングサークル" },
  { :id => 50, :category_id => 3, :order => "0303", :name => "モルック" , :ruby => "molkky",  :matching => 0, :place => 0, :openchat => "", :txt => "モルックサークル" },
  { :id => 28, :category_id => 3, :order => "0304", :name => "ゴルフ" , :ruby => "golf",  :matching => 0, :place => 0, :openchat => "", :txt => "ゴルフサークル" },
  { :id => 29, :category_id => 3, :order => "0305", :name => "ボウリング" , :ruby => "bowling",  :matching => 0, :place => 0, :openchat => "", :txt => "ボウリングサークル" },
  { :id => 17, :category_id => 3, :order => "0306", :name => "ロードバイク" , :ruby => "road-bike",  :matching => 0, :place => 0, :openchat => "", :txt => "ロードバイクサークル" },
  { :id => 51, :category_id => 3, :order => "0307", :name => "サバゲー" , :ruby => "airsoft",  :matching => 0, :place => 0, :openchat => "", :txt => "サバゲーサークル" },
  { :id => 30, :category_id => 3, :order => "0308", :name => "水泳" , :ruby => "swimming",  :matching => 0, :place => 0, :openchat => "", :txt => "水泳サークル・チーム" },
  { :id => 31, :category_id => 3, :order => "0309", :name => "カバディ" , :ruby => "kabaddi",  :matching => 0, :place => 0, :openchat => "", :txt => "カバディサークル・チーム" },
  { :id => 15, :category_id => 3, :order => "0310", :name => "総合格闘技" , :ruby => "mma",  :matching => 0, :place => 0, :openchat => "", :txt => "総合格闘技サークル" },
  { :id => 46, :category_id => 3, :order => "0311", :name => "その他のスポーツ" , :ruby => "other-sports",  :matching => 0, :place => 0, :openchat => "", :txt => "スポーツサークル" },


  # ウィンタースポーツ
  { :id => 20, :category_id => 4, :order => "0401", :name => "スノーボード" , :ruby => "snow-board",  :matching => 0, :place => 0, :openchat => "", :txt => "スノーボードサークル" },
  { :id => 32, :category_id => 4, :order => "0402", :name => "アイスホッケー" , :ruby => "ice-hockey",  :matching => 0, :place => 0, :openchat => "", :txt => "アイスホッケーサークル" },


  # 写真・動画
  { :id => 1, :category_id => 5, :order => "0501", :name => "写真・カメラ" , :ruby => "camera",  :matching => 0, :place => 0, :openchat => "https://line.me/ti/g2/MrGVZOgwkBEGzRpvagL-Cw", :txt => "写真・カメラサークル" },
  { :id => 45, :category_id => 5, :order => "0502", :name => "動画・映画" , :ruby => "movie",  :matching => 0, :place => 0, :openchat => "", :txt => "動画・映画サークル" },


  # アウトドア
  { :id => 18, :category_id => 6, :order => "0601", :name => "登山" , :ruby => "mountain",  :matching => 0, :place => 0, :openchat => "", :txt => "登山サークル" },
  { :id => 39, :category_id => 6, :order => "0602", :name => "キャンプ" , :ruby => "camping",  :matching => 0, :place => 0, :openchat => "", :txt => "キャンプサークル" },
  { :id => 52, :category_id => 6, :order => "0603", :name => "釣り" , :ruby => "fishing",  :matching => 0, :place => 0, :openchat => "", :txt => "釣りサークル" },
  { :id => 54, :category_id => 6, :order => "0604", :name => "ダイビング" , :ruby => "diving",  :matching => 0, :place => 0, :openchat => "", :txt => "ダイビングサークル" },


  # ゲーム
  { :id => 11, :category_id => 7, :order => "0701", :name => "ボードゲーム" , :ruby => "game",  :matching => 1, :place => 0, :openchat => "", :txt => "ボードゲームサークル" },
  { :id => 58, :category_id => 7, :order => "0702", :name => "ゲーム機" , :ruby => "game-console",  :matching => 1, :place => 0, :openchat => "", :txt => "ゲーム機で遊ぶサークル" },
  { :id => 41, :category_id => 7, :order => "0703", :name => "ダーツ・ビリヤード" , :ruby => "darts",  :matching => 0, :place => 0, :openchat => "", :txt => "ダーツ・ビリヤードサークル" },
  { :id => 42, :category_id => 7, :order => "0704", :name => "麻雀" , :ruby => "mahjong",  :matching => 0, :place => 0, :openchat => "", :txt => "麻雀サークル" },


  # 交流・学び
  { :id => 12, :category_id => 8, :order => "0801", :name => "イベント" , :ruby => "event",  :matching => 0, :place => 0, :openchat => "", :txt => "イベントサークル" },
  { :id => 34, :category_id => 8, :order => "0802", :name => "英会話" , :ruby => "english",  :matching => 0, :place => 0, :openchat => "", :txt => "英会話サークル" },
  { :id => 44, :category_id => 8, :order => "0803", :name => "勉強会・研究" , :ruby => "study",  :matching => 0, :place => 0, :openchat => "", :txt => "勉強会・研究サークル" },
  { :id => 33, :category_id => 8, :order => "0804", :name => "読書会" , :ruby => "reading",  :matching => 0, :place => 0, :openchat => "", :txt => "読書会・読書サークル" },
  { :id => 37, :category_id => 8, :order => "0805", :name => "散策・散歩" , :ruby => "go-out",  :matching => 0, :place => 0, :openchat => "", :txt => "散策・散歩サークル" },
  { :id => 36, :category_id => 8, :order => "0806", :name => "交流会・カフェ会" , :ruby => "gathering",  :matching => 0, :place => 0, :openchat => "", :txt => "交流会・カフェ会サークル" },
  { :id => 35, :category_id => 8, :order => "0807", :name => "街コン・オフ会" , :ruby => "meet-up",  :matching => 0, :place => 0, :openchat => "", :txt => "街コン・オフ会サークル" },
  { :id => 57, :category_id => 8, :order => "0808", :name => "チャット" , :ruby => "chat",  :matching => 0, :place => 0, :openchat => "", :txt => "グループチャット" },
  { :id => 24, :category_id => 8, :order => "0809", :name => "学生団体・インカレ" , :ruby => "student-group",  :matching => 0, :place => 0, :openchat => "", :txt => "学生団体・インカレ" },
  { :id => 26, :category_id => 8, :order => "0810", :name => "ボランティア" , :ruby => "volunteer",  :matching => 0, :place => 0, :openchat => "", :txt => "ボランティアサークル" },

  # 趣味
  { :id => 48, :category_id => 12, :order => "0901", :name => "料理" , :ruby => "cooking",  :matching => 0, :place => 0, :openchat => "", :txt => "料理サークル" },
  { :id => 38, :category_id => 12, :order => "0902", :name => "イラスト" , :ruby => "illustration",  :matching => 0, :place => 0, :openchat => "", :txt => "イラストサークル" },
  { :id => 55, :category_id => 12, :order => "0903", :name => "温泉・サウナ" , :ruby => "hot-spring",  :matching => 0, :place => 0, :openchat => "", :txt => "温泉・サウナサークル" },


  # 音楽・演劇
  { :id => 56, :category_id => 9, :order => "1001", :name => "バンド" , :ruby => "band",  :matching => 0, :place => 0, :openchat => "", :txt => "バンドサークル" },
  { :id => 13, :category_id => 9, :order => "1002", :name => "音楽" , :ruby => "music",  :matching => 0, :place => 0, :openchat => "", :txt => "音楽サークル" },
  { :id => 40, :category_id => 9, :order => "1003", :name => "演劇" , :ruby => "theater",  :matching => 0, :place => 0, :openchat => "", :txt => "演劇サークル" },


  # 踊る
  { :id => 19, :category_id => 10, :order => "1111", :name => "ダンス" , :ruby => "dance",  :matching => 0, :place => 0, :openchat => "", :txt => "ダンスサークル" },
  { :id => 14, :category_id => 10, :order => "1102", :name => "よさこい" , :ruby => "yosakoi",  :matching => 0, :place => 0, :openchat => "", :txt => "よさこいチーム・サークル" },


  # フィットネス
  { :id => 27, :category_id => 11, :order => "1201", :name => "ヨガ" , :ruby => "yoga",  :matching => 0, :place => 0, :openchat => "", :txt => "ヨガサークル" },
  { :id => 6, :category_id => 11, :order => "1202", :name => "筋トレ・合トレ" , :ruby => "work-out",  :matching => 0, :place => 0, :openchat => "", :txt => "筋トレ・合トレ" },


  { :id => 59, :category_id => 2, :order => "0206", :name => "ソフトテニス", :ruby => "soft-tennis", :matching => 0, :place => 0, :openchat => "", :txt => "ソフトテニスサークル" },
  { :id => 60, :category_id => 2, :order => "0207", :name => "ピックルボール", :ruby => "pickleball", :matching => 0, :place => 0, :openchat => "", :txt => "ピックルボールサークル" },
  { :id => 61, :category_id => 4, :order => "0403", :name => "スキー", :ruby => "ski", :matching => 0, :place => 0, :openchat => "", :txt => "スキーサークル" },
  { :id => 62, :category_id => 3, :order => "03105", :name => "空手", :ruby => "karate", :matching => 0, :place => 0, :openchat => "", :txt => "空手サークル" },
  { :id => 63, :category_id => 12, :order => "0904", :name => "手芸・ハンドメイド", :ruby => "handicraft", :matching => 0, :place => 0, :openchat => "", :txt => "手芸・ハンドメイドサークル" },
  { :id => 64, :category_id => 9, :order => "1004", :name => "カラオケ", :ruby => "karaoke", :matching => 0, :place => 0, :openchat => "", :txt => "カラオケサークル" },

  # その他
  { :id => 99, :category_id => 99, :order => "9999", :name => "その他" , :ruby => "other",  :matching => 0, :place => 0, :openchat => "", :txt => "その他のサークル" }

)
