"""ブラウザで観察済みの商品候補を原稿へ対応付ける。外部通信なし。"""
import json,re
from pathlib import Path
R=Path(__file__).parent
A=json.loads((R/'articles.json').read_text())
O=json.loads((R/'amazon-observations.json').read_text())
E=json.loads((R/'events.json').read_text())
aliases={
 'エツミ カメラ レインカバー':('ハクバ カメラ レインカバー',3),
 '無印良品 ナイロンメッシュスパポーチ':('無印良品 ポリエステル メッシュ ポーチ',0),
 'ダイワ 快適職人サビキ ショートMIX':('ダイワ サビキ 釣り セット',0),
 'キングジム カキコ A4':('コクヨ 楽譜 ファイル A4',5),
}
indices={
 'ミズノ 野球 ソフトボール 練習パンツ':3,
 'ミズノ ソフトボール グラブ 一般':1,
 'ASICS テニスシューズ オールコート':5,
 'ミズノ スポーツタオル':1,
 'ハクバ レンズ クリーニングクロス':4,
 '無印良品 衣類 仕分け ケース':5,
 'ゴールドジム トレーニンググローブ':1,
 'ミズノ ゴルフ クラブケース':2,
 'ダイワ 固型式 ライフジャケット':6,
 'ABS ボウリング マイクロファイバー タオル':1,
 '三菱鉛筆 色鉛筆 24色':1,
 'マルマン 図案 スケッチブック A4':7,
 'クロバー ロールメジャー':2,
 'エルスタイル エルシャフト':1,
 '無印良品 収納 ポーチ':1,
 '貝印 おたま':6,
 'タニタ デジタル クッキングスケール':1,
 'カモ井 マスキングテープ':2,
 'ジョイ 食器用洗剤':1,
 'ボードゲーム プレイマット':1,
}
catalog={}
for a in A:
 a['event_id']=int(E[a['event']])
 for p in a['products']:
  q,i=aliases.get(p['query'],(p['query'],indices.get(p['query'],0)))
  c=O[q][i]
  p.update(image_url=c['image_url'],verified_asin=c['asin'],image_example_title=c['title'],research_source='https://www.amazon.co.jp/dp/'+c['asin'])
  p['description']+='画像は検索候補の一例です。'
  catalog[p['query']]=c
 (R/(a['key']+'.md')).write_text('# '+a['title']+'\n\n広告：この記事にはアフィリエイトリンクが含まれます。\n\n'+(R/(a['key']+'.md')).read_text().split('\n\n',1)[1])
(R/'articles.json').write_text(json.dumps(A,ensure_ascii=False,indent=2)+'\n')
(R/'selected-products.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
for a in A:
 count=int(re.search(r'(\d+)選',a['title']).group(1))
 assert count==len(a['products'])
 assert len([b for b in a['blocks'] if re.fullmatch(r'\[商品:\d+\]',b['text'])])==count
 assert '|' not in a['title'] and '｜' not in a['title']
 assert len(a['description'])<=160
 assert all('tag=fieldnote482-22' in p['amazon_url'] and p['image_url'].startswith('https://m.media-amazon.com/') for p in a['products'])
print('validated',len(A),'articles /',sum(len(a['products']) for a in A),'cards')
