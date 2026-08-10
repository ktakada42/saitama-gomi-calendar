import { describe, expect, it } from 'vitest';

import { MICRO, microJpyOfNeurons, type Limits } from '../src/config';
import { hashIp, parseSortRequest } from '../src/request';
import { buildPrompt, pickIndex, textOf } from '../src/model';

const LIMITS: Limits = {
  maxOutputTokens: 2048,
  maxQuestionChars: 10,
  maxCandidates: 3,
  maxCandidateChars: 8,
  deviceDailyLimit: 20,
  ipDailyLimit: 60,
  ipBurstLimit: 5,
  dailyBudgetMicroJpy: 300 * MICRO,
  monthlyBudgetMicroJpy: 3000 * MICRO,
};

const DEVICE = '11111111-2222-3333-4444-555555555555';

function parse(body: unknown) {
  return parseSortRequest(body, LIMITS);
}

describe('受け取った中身を検める', () => {
  it('揃っていれば通す', () => {
    const result = parse({ deviceId: DEVICE, question: ' 傘 ', candidates: ['かさ'] });
    expect(result).toEqual({
      ok: true,
      value: { deviceId: DEVICE, question: '傘', candidates: ['かさ'] },
    });
  });

  it('端末IDがUUIDでなければ断る', () => {
    // 好きな文字列を名乗れると、数え上げの置き場をいくらでも作られる。
    for (const deviceId of ['', 'abc', 'x'.repeat(200), 123, null]) {
      expect(parse({ deviceId, question: '傘', candidates: ['かさ'] })).toMatchObject({
        ok: false,
        error: { field: 'deviceId' },
      });
    }
  });

  it('質問文が長すぎれば断る', () => {
    expect(
      parse({ deviceId: DEVICE, question: 'あ'.repeat(11), candidates: ['かさ'] }),
    ).toMatchObject({ ok: false, error: { field: 'question' } });
  });

  it('長さは文字数で見る', () => {
    // 絵文字や結合文字を「.length」で数えると、見た目より長く出て
    // 正しい入力まで断ってしまう。
    expect(
      parse({ deviceId: DEVICE, question: '🍙'.repeat(10), candidates: ['かさ'] }),
    ).toMatchObject({ ok: true });
  });

  it('空の質問は断る', () => {
    for (const question of ['', '   ', '\n']) {
      expect(parse({ deviceId: DEVICE, question, candidates: ['かさ'] })).toMatchObject({
        ok: false,
        error: { field: 'question' },
      });
    }
  });

  it('候補が多すぎれば断る', () => {
    expect(
      parse({ deviceId: DEVICE, question: '傘', candidates: ['あ', 'い', 'う', 'え'] }),
    ).toMatchObject({ ok: false, error: { field: 'candidates' } });
  });

  it('候補の1件が長すぎれば断る', () => {
    // 候補はそのままプロンプトに入る。ここを開けておくと、
    // 件数の上限を守ったまま長文を送り込める。
    expect(
      parse({ deviceId: DEVICE, question: '傘', candidates: ['あ'.repeat(9)] }),
    ).toMatchObject({ ok: false, error: { field: 'candidates' } });
  });

  it('候補が空なら断る', () => {
    expect(parse({ deviceId: DEVICE, question: '傘', candidates: [] })).toMatchObject({
      ok: false,
      error: { field: 'candidates' },
    });
  });

  it('オブジェクトでなければ断る', () => {
    for (const body of [null, 'abc', 42, []]) {
      expect(parse(body)).toMatchObject({ ok: false });
    }
  });
});

describe('IPの取り扱い', () => {
  it('同じIPは同じ値になり、違うIPは違う値になる', async () => {
    const a = await hashIp('203.0.113.1', 'salt');
    expect(await hashIp('203.0.113.1', 'salt')).toBe(a);
    expect(await hashIp('203.0.113.2', 'salt')).not.toBe(a);
  });

  it('種が違えば値も変わる', async () => {
    // 保存された値だけを見ても、どのIPだったかは辿れない。
    expect(await hashIp('203.0.113.1', 'salt-a')).not.toBe(
      await hashIp('203.0.113.1', 'salt-b'),
    );
  });

  it('元のIPが残らない', async () => {
    expect(await hashIp('203.0.113.1', 'salt')).not.toContain('203');
  });
});

describe('答えの読み取り', () => {
  const candidates = ['かさ', 'ペットボトル', '電池'];

  it('選ばれた品目を番号に直す', () => {
    expect(pickIndex('{"item": "ペットボトル"}', candidates)).toBe(1);
  });

  it('前後に説明が付いていても読む', () => {
    expect(pickIndex('はい。\n{"item": "電池"}\n以上です', candidates)).toBe(2);
  });

  it('考えを書いてから答えるモデルでも、最後の答えを採る', () => {
    // 選んだモデルは答える前に考える。前から採ると、考えの途中に出てくる
    // 例のほうを拾ってしまう。
    const thinking =
      'まず{"item": "かさ"}かと思ったが、よく見ると違う。\n{"item": "電池"}';
    expect(pickIndex(thinking, candidates)).toBe(2);
  });

  it('該当なしは null', () => {
    expect(pickIndex('{"item": null}', candidates)).toBeNull();
  });

  it('候補に無い名前は捨てる', () => {
    // ここが最後の関門。候補に無い答えを通すと、市の資料に無い区分が
    // 画面に出てしまう。捨てておけば、その道が構造として塞がる。
    expect(pickIndex('{"item": "もえるごみ"}', candidates)).toBeNull();
    expect(pickIndex('{"item": "宇宙船"}', candidates)).toBeNull();
  });

  it('JSONでなければ null', () => {
    for (const text of ['', 'かさです', '{壊れた', '{"item": 42}', '{"other": "かさ"}']) {
      expect(pickIndex(text, candidates)).toBeNull();
    }
  });
});

describe('プロンプト', () => {
  it('質問と候補を差し込む', () => {
    const prompt = buildPrompt('こわれた傘', ['かさ', '電池']);
    expect(prompt).toContain('こわれた傘');
    expect(prompt).toContain('- かさ\n- 電池');
  });

  it('出力の形の指示が残っている', () => {
    // #41 で測ったときと同じ指示であること。ここが変わると精度も変わる。
    expect(buildPrompt('傘', ['かさ'])).toContain('{"item": "選んだ品目名、または該当なしなら null"}');
  });
});

describe('費用の計算', () => {
  const price = { usdJpy: 160, usdPer1kNeurons: 0.011 };

  it('実際のneuron数から円を出す', () => {
    // 14.1 neuron ÷ 1000 × $0.011 × 160円 = 0.024816円。
    // 14.1 は検証（scripts/ai_eval/）での1問あたりの実測値。
    expect(microJpyOfNeurons(14.1, price)).toBe(24_816);
  });

  it('0なら0', () => {
    expect(microJpyOfNeurons(0, price)).toBe(0);
  });

  it('使った量に比例する', () => {
    expect(microJpyOfNeurons(28.2, price)).toBe(2 * microJpyOfNeurons(14.1, price));
  });
});

describe('応答の読み取り', () => {
  it('choices に入る形を読む', () => {
    expect(textOf({ choices: [{ message: { content: ' かさ ' } }] })).toBe('かさ');
  });

  it('response に入る形を読む', () => {
    expect(textOf({ response: ' かさ ' })).toBe('かさ');
  });

  it('両方あって choices が空なら response を採る', () => {
    // モデルによっては両方の鍵を持ち、片方が空で返る。
    expect(textOf({ choices: [{ message: { content: null } }], response: 'かさ' }))
      .toBe('かさ');
  });

  it('どちらも無ければ空', () => {
    expect(textOf({})).toBe('');
    expect(textOf({ response: null })).toBe('');
  });
});
