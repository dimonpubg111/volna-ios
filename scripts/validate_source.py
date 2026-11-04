"""Structural checks on Windows. This is not an iOS compiler or device test."""
from pathlib import Path
import json, plistlib, sys, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
tooling = ROOT.parent/'validation-lib'
if tooling.exists(): sys.path.insert(0, str(tooling))
import tree_sitter, tree_sitter_swift
from openstep_parser import OpenStepDecoder

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
swift_files = sorted(ROOT.glob('VOLNA*/*.swift'))
for source in swift_files:
    content = source.read_bytes()
    tree = parser.parse(content)
    def scan(node):
        if node.type == 'ERROR' or node.is_missing:
            failures.append(f'{source.name}:{node.start_point.row+1}:{node.start_point.column+1}: {node.type}: {content[node.start_byte:node.end_byte][:120]!r}')
        for child in node.children: scan(child)
    scan(tree.root_node)
    if b'import WebKit' in content or b'WKWebView' in content:
        failures.append(f'{source.name}: web wrapper remains')

with (ROOT/'VOLNA.xcodeproj/project.pbxproj').open(encoding='utf-8') as stream:
    project = OpenStepDecoder.ParseFromFile(stream)
objects = project['objects']
assert project['rootObject'] in objects
assert len([x for x in objects.values() if x['isa'] == 'PBXNativeTarget']) == 3
sources = [x for x in objects.values() if x['isa'] == 'PBXFileReference' and x.get('lastKnownFileType') == 'sourcecode.swift']
assert len(sources) == len(swift_files)
for source in sources:
    assert any(p.name == source['path'] for p in swift_files), source
for value in objects.values():
    for key in ['fileRef','buildConfigurationList','mainGroup','productReference','target','targetProxy','containerPortal']:
        if key in value: assert value[key] in objects, (key,value)
    for key in ['files','buildPhases','children','targets','dependencies','buildConfigurations']:
        for reference in value.get(key,[]): assert reference in objects, (key,reference)

for name in ['Info.plist','PrivacyInfo.xcprivacy']:
    with (ROOT/'VOLNA'/name).open('rb') as stream: plistlib.load(stream)
info = plistlib.loads((ROOT/'VOLNA/Info.plist').read_bytes())
assert 'audio' in info['UIBackgroundModes']
assert 'NSAllowsArbitraryLoads' not in str(info)
scheme = ET.parse(ROOT/'VOLNA.xcodeproj/xcshareddata/xcschemes/VOLNA.xcscheme')
for ref in scheme.iter('BuildableReference'): assert ref.attrib['BlueprintIdentifier'] in objects
catalogue = json.loads((ROOT/'VOLNA/catalog.json').read_text(encoding='utf-8'))
assert len(catalogue['channels']) == 155
assert [c['id'] for c in catalogue['channels'][:3]] == ['novyi','tet','stb']
assert len({c['id'] for c in catalogue['channels']}) == len(catalogue['channels'])
for data in ROOT.glob('VOLNA/Assets.xcassets/**/Contents.json'): json.loads(data.read_text())
if failures:
    print('\n'.join(failures)); raise SystemExit(1)
print(json.dumps({'swiftFilesParsed':len(swift_files),'swiftSyntaxErrors':0,'projectObjects':len(objects),'targets':3,'catalogueChannels':len(catalogue['channels']),'webView':False,'appleCompilationPerformed':False},indent=2))
