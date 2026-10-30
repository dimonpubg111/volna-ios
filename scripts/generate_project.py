"""Generate a dependency-free Xcode project; never overwrite application sources."""
from pathlib import Path
import hashlib, json, plistlib

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(identifier, isa, **values):
    key = uid(identifier)
    objects[key] = dict(isa=isa, **values)
    return key
def encode(value):
    if isinstance(value, dict):
        return '{\n' + '\n'.join(f'{json.dumps(str(k))} = {encode(v)};' for k, v in value.items()) + '\n}'
    if isinstance(value, list):
        return '(' + ','.join(encode(v) for v in value) + ')'
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)

app_id, tests_id, ui_id, project_id = [uid(k) for k in ['app-target', 'test-target', 'ui-target', 'project']]
source_refs = []
app_build = []
resources = []
for source in sorted((ROOT/'VOLNA').glob('*.swift')):
    ref = add('source-'+source.name, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=source.name, sourceTree='<group>')
    source_refs.append(ref)
    app_build.append(add('build-'+source.name, 'PBXBuildFile', fileRef=ref))
for name, kind in [('Assets.xcassets', 'folder.assetcatalog'), ('catalog.json', 'text.json'), ('PrivacyInfo.xcprivacy', 'text.xml')]:
    ref = add('resource-'+name, 'PBXFileReference', lastKnownFileType=kind, path=name, sourceTree='<group>')
    source_refs.append(ref)
    resources.append(add('build-resource-'+name, 'PBXBuildFile', fileRef=ref))
source_refs.append(add('info', 'PBXFileReference', lastKnownFileType='text.plist.xml', path='Info.plist', sourceTree='<group>'))
app_group = add('app-group', 'PBXGroup', children=source_refs, path='VOLNA', sourceTree='<group>')
products = []
targets = []
groups = [app_group]

def configurations(name, settings):
    refs = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        values.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if mode == 'Debug' else 'dwarf-with-dsym')
        if mode == 'Debug': values.update(ENABLE_TESTABILITY='YES', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG')
        refs.append(add(name+'-'+mode, 'XCBuildConfiguration', name=mode, buildSettings=values))
    return add(name+'-list', 'XCConfigurationList', buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

base = dict(SDKROOT='iphoneos', IPHONEOS_DEPLOYMENT_TARGET='17.0', SWIFT_VERSION='5.0', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES', ENABLE_USER_SCRIPT_SANDBOXING='YES', SWIFT_STRICT_CONCURRENCY='targeted')
project_config = configurations('project-config', base)
for name, target_id, folder, files, resource_files, is_ui in [
    ('VOLNA', app_id, 'VOLNA', app_build, resources, False),
    ('VOLNATests', tests_id, 'VOLNATests', [], [], False),
    ('VOLNAUITests', ui_id, 'VOLNAUITests', [], [], True),
]:
    app = name == 'VOLNA'
    if not app:
        children = []
        for source in sorted((ROOT/folder).glob('*.swift')):
            ref = add('test-source-'+source.name, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=source.name, sourceTree='<group>')
            children.append(ref)
            files.append(add('test-build-'+source.name, 'PBXBuildFile', fileRef=ref))
        groups.append(add(name+'-group', 'PBXGroup', path=folder, children=children, sourceTree='<group>'))
        if not is_ui:
            resource_files.append(add('test-catalogue', 'PBXBuildFile', fileRef=uid('resource-catalog.json')))
    extension = 'app' if app else 'xctest'
    product = add(name+'-product', 'PBXFileReference', explicitFileType='wrapper.application' if app else 'wrapper.cfbundle', includeInIndex=0, path=name+'.'+extension, sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product)
    phases = [
        add(name+'-sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0),
        add(name+'-frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
        add(name+'-resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=resource_files, runOnlyForDeploymentPostprocessing=0),
    ]
    settings = dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER='com.volna.cinema' + ('' if app else '.'+name), CODE_SIGN_STYLE='Automatic', TARGETED_DEVICE_FAMILY='1,2', CURRENT_PROJECT_VERSION='21', MARKETING_VERSION='2.1.0', SWIFT_EMIT_LOC_STRINGS='YES')
    if app:
        settings.update(INFOPLIST_FILE='VOLNA/Info.plist', GENERATE_INFOPLIST_FILE='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/Frameworks', SUPPORTS_MACCATALYST='NO')
    else:
        settings.update(GENERATE_INFOPLIST_FILE='YES')
        if is_ui: settings.update(TEST_TARGET_NAME='VOLNA')
        else: settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/VOLNA.app/VOLNA', BUNDLE_LOADER='$(TEST_HOST)')
    deps = []
    if not app:
        proxy = add(name+'-proxy', 'PBXContainerItemProxy', containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_id, remoteInfo='VOLNA')
        deps.append(add(name+'-dependency', 'PBXTargetDependency', target=app_id, targetProxy=proxy))
    objects[target_id] = dict(isa='PBXNativeTarget', buildConfigurationList=configurations(name+'-config', settings), buildPhases=phases, buildRules=[], dependencies=deps, name=name, productName=name, productReference=product, productType='com.apple.product-type.application' if app else 'com.apple.product-type.bundle.ui-testing' if is_ui else 'com.apple.product-type.bundle.unit-test')
    targets.append(target_id)

product_group = add('products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
main_group = add('main-group', 'PBXGroup', children=groups+[product_group], sourceTree='<group>')
objects[project_id] = dict(isa='PBXProject', attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2600','TargetAttributes':{app_id:{'CreatedOnToolsVersion':'26.0'},tests_id:{'CreatedOnToolsVersion':'26.0','TestTargetID':app_id},ui_id:{'CreatedOnToolsVersion':'26.0','TestTargetID':app_id}}}, buildConfigurationList=project_config, compatibilityVersion='Xcode 14.0', developmentRegion='uk', hasScannedForEncodings=0, knownRegions=['uk','en','Base'], mainGroup=main_group, productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets)
project = ROOT/'VOLNA.xcodeproj'
project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project_id))+'\n', encoding='utf-8')
scheme_dir = project/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:VOLNA.xcodeproj"/>'
app_ref = buildable(app_id, 'VOLNA.app')
test_refs = ''.join(f'<TestableReference skipped="NO">{buildable(t,n)}</TestableReference>' for t,n in [(tests_id,'VOLNATests.xctest'),(ui_id,'VOLNAUITests.xctest')])
(scheme_dir/'VOLNA.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{test_refs}</Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
print(f'Generated project: {len(objects)} objects, {len(app_build)} application sources, 3 targets')
