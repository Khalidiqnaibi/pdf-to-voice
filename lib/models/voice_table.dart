/// Maps Kokoro voice names to the speaker ids the engine addresses them by.
///
/// The engine indexes voices by position in `voices.bin`, which is *almost* the
/// alphabetical order of the names — except `em_santa` sits at the end rather
/// than in sequence, shifting every voice after it by one. Assuming sorted
/// order silently returns the wrong speaker for 24 of the 54 voices.
///
/// This list was not guessed: each entry was confirmed by matching the raw
/// style-embedding vectors in `voices.bin` against the named vectors in the
/// Kokoro voice pack. All 54 matched exactly, with no duplicates and none left
/// over.
library;

/// Voice names in speaker-id order. The index *is* the speaker id.
const kokoroVoicesBySid = <String>[
  'af_alloy', // 0
  'af_aoede',
  'af_bella',
  'af_heart',
  'af_jessica',
  'af_kore',
  'af_nicole',
  'af_nova',
  'af_river',
  'af_sarah',
  'af_sky', // 10
  'am_adam',
  'am_echo',
  'am_eric',
  'am_fenrir',
  'am_liam',
  'am_michael',
  'am_onyx',
  'am_puck',
  'am_santa',
  'bf_alice', // 20
  'bf_emma',
  'bf_isabella',
  'bf_lily',
  'bm_daniel',
  'bm_fable',
  'bm_george',
  'bm_lewis',
  'ef_dora',
  'em_alex',
  'ff_siwis', // 30 — em_santa would be here in sorted order
  'hf_alpha',
  'hf_beta',
  'hm_omega',
  'hm_psi',
  'if_sara',
  'im_nicola',
  'jf_alpha',
  'jf_gongitsune',
  'jf_nezumi',
  'jf_tebukuro', // 40
  'jm_kumo',
  'pf_dora',
  'pm_alex',
  'pm_santa',
  'zf_xiaobei',
  'zf_xiaoni',
  'zf_xiaoxiao',
  'zf_xiaoyi',
  'zm_yunjian',
  'zm_yunxi', // 50
  'zm_yunxia',
  'zm_yunyang',
  'em_santa', // 53 — out of alphabetical sequence
];

final _sidByName = <String, int>{
  for (var i = 0; i < kokoroVoicesBySid.length; i++) kokoroVoicesBySid[i]: i,
};

/// Speaker id for a voice name, or null if the name is not in the pack.
int? sidForVoice(String name) => _sidByName[name];
