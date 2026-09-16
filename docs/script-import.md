# Script import

The selected presentation's Import Script action presents the native Files picker. It can read user-selected files from On My iPhone, iCloud Drive and installed File Provider extensions. If that presentation already contains text, FollowScript asks before replacing it. The imported text is then autosaved as the selected presentation's script and is the text used by the teleprompter.

## Supported formats

- Word Open XML: `.docx`
- OpenDocument Text: `.odt`
- Markdown: `.md`, `.markdown`
- Plain text: `.txt`, `.text`
- Rich Text Format: `.rtf`
- HTML: `.html`, `.htm`

Import produces editable plain text. Markdown markers and rich-document formatting are removed. Images, tables as structured layouts, headers, footers, comments, footnotes and tracked-change metadata are not preserved. Legacy binary Word `.doc` files are not supported.

DOCX and ODT are read locally as ZIP-packaged XML. Only `word/document.xml` or `content.xml` is extracted, with support for stored and DEFLATE-compressed entries. Archives larger than 50 MiB, extracted text payloads larger than 10 MiB, encrypted archives, ZIP64 and uncommon compression methods are rejected with a user-facing error.

The importer calls `startAccessingSecurityScopedResource()` for the URL returned by the system picker and balances successful access with `stopAccessingSecurityScopedResource()`. It retains only the extracted text in the selected presentation through `AppModel` and `PresentationProjectStore`; it does not retain the source URL, bookmark or source document.
