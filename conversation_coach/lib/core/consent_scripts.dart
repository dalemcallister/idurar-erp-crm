/// Localised, read-aloud consent scripts and jurisdiction notes (F-CON-01/04,
/// Design §6.1). Guidance only — never presented as legal advice (Tech Spec §8).
///
/// Launch languages: English, Mandarin and Malay, with code-switching support
/// (Design §8 — South-East Asia focus).
class ConsentScripts {
  static const Map<String, String> languageNames = {
    'en': 'English',
    'zh': 'Mandarin (中文)',
    'ms': 'Malay (Bahasa Melayu)',
  };

  /// A short script the user reads aloud before recording.
  static String script(String language) {
    switch (language) {
      case 'zh':
        return '为了帮助我提升沟通能力，我想录制这次对话。'
            '录音只会保存在我的设备上。请问您同意吗？';
      case 'ms':
        return 'Untuk membantu saya menambah baik komunikasi, saya ingin '
            'merakam perbualan ini. Rakaman akan disimpan pada peranti saya '
            'sahaja. Adakah anda bersetuju?';
      case 'en':
      default:
        return 'To help me improve how I communicate, I\'d like to record this '
            'conversation. The recording stays on my device. Is that okay with you?';
    }
  }

  /// Jurisdiction guidance — one-party vs all-party consent, etc. Not legal
  /// advice (F-CON-04).
  static String jurisdictionNote(String language) {
    switch (language) {
      case 'zh':
        return '提示：录音同意的法律要求因地区而异（有些地区要求所有'
            '参与方同意）。本提示仅供参考，不构成法律意见。';
      case 'ms':
        return 'Nota: keperluan undang-undang bagi rakaman berbeza mengikut '
            'bidang kuasa (sesetengah memerlukan persetujuan semua pihak). '
            'Ini panduan sahaja, bukan nasihat undang-undang.';
      case 'en':
      default:
        return 'Note: consent rules vary by jurisdiction — some require all '
            'parties to agree, others only one. This is guidance, not legal advice.';
    }
  }
}
