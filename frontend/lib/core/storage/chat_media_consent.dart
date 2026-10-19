/// The student's answer to "save chat pictures and PDFs on this phone?".
/// Nothing is downloaded to the phone until it's [save] — see
/// ChatMediaStore.
enum ChatMediaConsent {
  undecided,
  save,
  dontSave;

  static ChatMediaConsent fromName(String? name) =>
      ChatMediaConsent.values.firstWhere((v) => v.name == name, orElse: () => ChatMediaConsent.undecided);
}
