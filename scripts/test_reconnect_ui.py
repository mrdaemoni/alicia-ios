"""Temporary XCUITest target for the real app; no changes to its project file."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-context-ui-'))
print(work, flush=True)
project = work / 'Alicia.xcodeproj'
shutil.copytree(root / 'Alicia.xcodeproj', project)
for folder in ('Alicia','AliciaWidgets','Shared'):
    (work / folder).symlink_to(root / folder, target_is_directory=True)
for source in root.glob('*.plist'):
    (work / source.name).symlink_to(source)
p = json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(project/'project.pbxproj')]))
o=p['objects']; r=o[p['rootObject']]
def add(suffix, value):
    key='CC00000000000000000000'+suffix
    o[key]=value
    return key
ref=add('01',dict(isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path='ContextUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR'))
group=add('02',dict(isa='PBXFileSystemSynchronizedRootGroup',explicitFileTypes={},explicitFolders=[],path='ContextUITests',sourceTree='<group>'))
sources=add('03',dict(isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
frameworks=add('04',dict(isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
configs=[]
for index, name in enumerate(('Debug','Release')):
    configs.append(add('0'+str(5+index),dict(isa='XCBuildConfiguration',name=name,buildSettings=dict(
        CODE_SIGN_STYLE='Automatic',GENERATE_INFOPLIST_FILE='YES',IPHONEOS_DEPLOYMENT_TARGET='18.0',
        PRODUCT_BUNDLE_IDENTIFIER='com.myalicia.contextuitests',PRODUCT_NAME='$(TARGET_NAME)',
        SWIFT_VERSION='5.0',TARGETED_DEVICE_FAMILY='1,2',TEST_TARGET_NAME='Alicia',SDKROOT='iphoneos'))))
configlist=add('07',dict(isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release'))
proxy=add('08',dict(isa='PBXContainerItemProxy',containerPortal=p['rootObject'],proxyType='1',remoteGlobalIDString='AA0000000000000000000006',remoteInfo='Alicia'))
dep=add('09',dict(isa='PBXTargetDependency',target='AA0000000000000000000006',targetProxy=proxy))
target=add('10',dict(isa='PBXNativeTarget',name='ContextUITests',productName='ContextUITests',productType='com.apple.product-type.bundle.ui-testing',
    productReference=ref,buildConfigurationList=configlist,buildPhases=[sources,frameworks],buildRules=[],dependencies=[dep],fileSystemSynchronizedGroups=[group]))
r['targets'].append(target);o[r['mainGroup']]['children'].append(group);o[r['productRefGroup']]['children'].append(ref)
(project/'project.pbxproj').write_bytes(plistlib.dumps(p))
scheme=project/'xcshareddata/xcschemes/Alicia.xcscheme';tree=ET.parse(scheme)
refattrs=dict(BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='ContextUITests.xctest',BlueprintName='ContextUITests',ReferencedContainer='container:Alicia.xcodeproj')
entry=ET.SubElement(tree.find('.//BuildActionEntries'),'BuildActionEntry',dict(buildForTesting='YES',buildForRunning='NO',buildForProfiling='NO',buildForArchiving='NO',buildForAnalyzing='NO'))
ET.SubElement(entry,'BuildableReference',refattrs)
test=ET.SubElement(tree.find('.//Testables'),'TestableReference',dict(skipped='NO'));ET.SubElement(test,'BuildableReference',refattrs)
tree.write(scheme,encoding='utf-8',xml_declaration=True)
(work/'ContextUITests').mkdir()
(work/'ContextUITests/ContextUITests.swift').write_text(r"""
import XCTest

/// A2-056 — a lost route retries before it accuses her of being unreachable.
///
/// Driven against a dead endpoint via the UserDefaults override, which is the
/// same precedence a debugger uses: the app runs LIVE (not mock) and every
/// read fails at the transport, exactly as it did when Hector's phone fell off
/// the Wi-Fi and Tailscale dropped to a relay.
final class ReconnectUITests: XCTestCase {
 func capture(_ name:String,_ app:XCUIApplication) {
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }
 func launchAgainstNothing() -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication()
  // 127.0.0.1:1 refuses immediately — a transport failure, not a timeout.
  app.launchArguments=["-alicia.baseURL","http://127.0.0.1:1","-alicia.token","synthetic-not-a-real-token"]
  app.launch()
  return app
 }

 func testItSaysItIsTryingBeforeItSaysSheIsUnreachable() {
  let app=launchAgainstNothing()
  let trying=app.staticTexts["reaching her…"]
  let dead=app.staticTexts["she's unreachable right now"]
  // The retry window is ~2.4s, so "reaching her" must appear first.
  XCTAssertTrue(trying.waitForExistence(timeout:10),"it never said it was trying")
  capture("reaching-her",app)
  XCTAssertTrue(dead.waitForExistence(timeout:25),"it never gave up honestly")
  capture("gave-up-honestly",app)
 }

 func testTheAppIsStillUsableWhileSheIsUnreachable() {
  let app=launchAgainstNothing()
  XCTAssertTrue(app.staticTexts["she's unreachable right now"].waitForExistence(timeout:30))
  // The band and the navigation are furniture: they do not depend on her.
  XCTAssertTrue(app.buttons["dialogue.composer"].exists)
  XCTAssertTrue(app.buttons["composer.walk"].exists)
  for name in ["US","MIND","BODY","ALICIA","STUDIO"] {
   XCTAssertTrue(app.buttons[name].exists,"\(name) vanished when she was unreachable")
  }
  capture("usable-while-unreachable",app)
 }
}
""")

env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('reconnect-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/ReconnectUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
