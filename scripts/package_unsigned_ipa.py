"""Package a real Xcode-built device .app for subsequent signing, never a fake IPA."""
from pathlib import Path
import os, plistlib, stat, sys, zipfile

app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
assert app.is_dir() and app.suffix == '.app', 'Pass an actual Xcode-built .app'
info = plistlib.loads((app/'Info.plist').read_bytes())
binary = app/info['CFBundleExecutable']
assert binary.is_file(), 'The compiled executable is missing'
with binary.open('rb') as stream:
    magic = stream.read(4)
assert magic in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'], 'Not a Mach-O executable'
assert info.get('DTPlatformName') == 'iphoneos', 'A simulator build cannot be installed on iPhone'
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob('*')):
        relative = Path('Payload')/app.name/file.relative_to(app)
        if file.is_symlink():
            entry = zipfile.ZipInfo(relative.as_posix())
            entry.create_system = 3; entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, os.readlink(file))
        elif file.is_file():
            archive.write(file, relative.as_posix())
print(f'Created {output.name}: UNSIGNED; Apple signing/re-signing is required before installation.')
