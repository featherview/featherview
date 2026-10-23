# Security

Featherview opens files from anywhere, and decodes some formats with its own code
(`Sources/FeatherviewCore/Formats/`) and vendored C libraries (`Sources/CJPEGXR`, `Sources/CJPEGXL`).
A file that crashes the app, hangs it, or makes it read or write outside the file is a security bug.

## Reporting

Please report privately: **Security › Report a vulnerability** on
<https://github.com/featherview/featherview/security>. Attach the file if you can (zipped), and say
which version you used. You'll get an answer within a week.

Plain crashes on a broken file that you're happy to share publicly can go to the issue tracker.

## Supported versions

Only the latest release gets fixes.
