# RS Dev Tools

Tools for RuneScape plugin makers: UI and plugin layer inspector, event monitor, sprite, item and sound browsers, diagnostics, error log with stack traces, API explorer and a developer FAQ.

Current version: 0.2.8

- Install from mod.io: https://mod.io/g/runescape/m/rs-dev-tools

## Submission checker
`tools/check_submission.py` checks a plugin folder for the file, manifest, code and listing rules that the in-game Submission Check tab cannot read (plugins have no file API):

```
python tools/check_submission.py path/to/your-plugin --listing path/to/listing-folder --zip your-plugin-1.0.0.zip
```

It prints PASS, WARN, FAIL or MANUAL for each rule and exits 1 on any FAIL.

## Report a bug or request a feature

Open an issue: https://github.com/MAX-Q00/rs-dev-tools/issues/new/choose

For a bug, please include the plugin version, what happened, what you expected, steps to reproduce, a screenshot if you can, and your game resolution and UI scale.

Contact: Dylan@quspace.agency

## EULA

This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

By submitting a Plugin (as defined in Schedule 4 of the EULA), you acknowledge that you agree to the terms of the Jagex End User License Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it be reference) and acknowledge that such terms are legally binding on you. If you do not agree to the terms of the EULA, you must not submit a Plugin or use the Plugin functionality anyway. In such circumstances, Jagex does not licence the software to you, or grant you any of the relevant rights relating to the submission of Plugins set out in the EULA and you will not be permitted to access or use the Plugin functionality in any way whatsoever.

---

Not affiliated with or endorsed by Jagex. RuneScape is a trademark of Jagex Ltd.
