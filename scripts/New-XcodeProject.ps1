$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$projectDirectory = Join-Path $workspace 'LinkAff.xcodeproj'
New-Item -ItemType Directory -Force -Path $projectDirectory | Out-Null
$sourceNames = @('Models.swift','URLValidator.swift','Storage.swift','Networking.swift','MockService.swift','AppModel.swift','LinkAffApp.swift','Views.swift','Brand.swift')
$objects = [System.Collections.Generic.List[string]]::new()
$references = [System.Collections.Generic.List[string]]::new()
$buildFiles = [System.Collections.Generic.List[string]]::new()
for ($index = 0; $index -lt $sourceNames.Count; $index++) {
    $reference = 'A00000000000000000000{0:D3}' -f $index
    $build = 'B00000000000000000000{0:D3}' -f $index
    $name = $sourceNames[$index]
    $objects.Add("$reference = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = $name; sourceTree = `"<group>`"; };")
    $objects.Add("$build = {isa = PBXBuildFile; fileRef = $reference; };")
    $references.Add($reference)
    $buildFiles.Add($build)
}
$referenceList = $references -join ', '
$buildList = $buildFiles -join ', '
$sourceObjects = $objects -join "`n"
$projectText = @"
// !`$*UTF8*`$!
{
archiveVersion = 1;
classes = {};
objectVersion = 56;
objects = {
$sourceObjects
C00000000000000000000001 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = LinkAff.app; sourceTree = BUILT_PRODUCTS_DIR; };
C00000000000000000000002 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = LinkAffTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
C00000000000000000000003 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LinkAffTests.swift; sourceTree = "<group>"; };
C00000000000000000000004 = {isa = PBXBuildFile; fileRef = C00000000000000000000003; };
C00000000000000000000005 = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
C00000000000000000000006 = {isa = PBXBuildFile; fileRef = C00000000000000000000005; };
C00000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
C00000000000000000000008 = {isa = PBXBuildFile; fileRef = C00000000000000000000007; };
D00000000000000000000001 = {isa = PBXGroup; children = (D00000000000000000000002, D00000000000000000000003, D00000000000000000000004); sourceTree = "<group>"; };
D00000000000000000000002 = {isa = PBXGroup; children = ($referenceList, C00000000000000000000005, C00000000000000000000007); path = LinkAff; sourceTree = "<group>"; };
D00000000000000000000003 = {isa = PBXGroup; children = (C00000000000000000000003); path = LinkAffTests; sourceTree = "<group>"; };
D00000000000000000000004 = {isa = PBXGroup; children = (C00000000000000000000001, C00000000000000000000002); name = Products; sourceTree = "<group>"; };
E00000000000000000000001 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ($buildList); runOnlyForDeploymentPostprocessing = 0; };
E00000000000000000000002 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (C00000000000000000000006, C00000000000000000000008); runOnlyForDeploymentPostprocessing = 0; };
E00000000000000000000003 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
E00000000000000000000004 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (C00000000000000000000004); runOnlyForDeploymentPostprocessing = 0; };
E00000000000000000000005 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
F00000000000000000000001 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000004; buildPhases = (E00000000000000000000001, E00000000000000000000003, E00000000000000000000002); buildRules = (); dependencies = (); name = LinkAff; productName = LinkAff; productReference = C00000000000000000000001; productType = "com.apple.product-type.application"; };
F00000000000000000000002 = {isa = PBXNativeTarget; buildConfigurationList = F00000000000000000000005; buildPhases = (E00000000000000000000004, E00000000000000000000005); buildRules = (); dependencies = (F00000000000000000000007); name = LinkAffTests; productName = LinkAffTests; productReference = C00000000000000000000002; productType = "com.apple.product-type.bundle.unit-test"; };
F00000000000000000000003 = {isa = XCConfigurationList; buildConfigurations = (100000000000000000000001, 100000000000000000000002); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
F00000000000000000000004 = {isa = XCConfigurationList; buildConfigurations = (100000000000000000000003, 100000000000000000000004); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
F00000000000000000000005 = {isa = XCConfigurationList; buildConfigurations = (100000000000000000000005, 100000000000000000000006); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
F00000000000000000000006 = {isa = PBXContainerItemProxy; containerPortal = 200000000000000000000001; proxyType = 1; remoteGlobalIDString = F00000000000000000000001; remoteInfo = LinkAff; };
F00000000000000000000007 = {isa = PBXTargetDependency; target = F00000000000000000000001; targetProxy = F00000000000000000000006; };
100000000000000000000001 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; }; name = Debug; };
100000000000000000000002 = {isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; }; name = Release; };
100000000000000000000003 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.LinkAff; PRODUCT_NAME = "`$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = LinkAff; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.shopping"; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1; }; name = Debug; };
100000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.LinkAff; PRODUCT_NAME = "`$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = LinkAff; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.shopping"; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1; }; name = Release; };
100000000000000000000005 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.LinkAffTests; PRODUCT_NAME = "`$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; TEST_HOST = "`$(BUILT_PRODUCTS_DIR)/LinkAff.app/`$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LinkAff"; BUNDLE_LOADER = "`$(TEST_HOST)"; }; name = Debug; };
100000000000000000000006 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.LinkAffTests; PRODUCT_NAME = "`$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; TEST_HOST = "`$(BUILT_PRODUCTS_DIR)/LinkAff.app/`$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LinkAff"; BUNDLE_LOADER = "`$(TEST_HOST)"; }; name = Release; };
200000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600; TargetAttributes = {F00000000000000000000001 = {CreatedOnToolsVersion = 16.0; }; F00000000000000000000002 = {CreatedOnToolsVersion = 16.0; TestTargetID = F00000000000000000000001; }; }; }; buildConfigurationList = F00000000000000000000003; compatibilityVersion = "Xcode 14.0"; developmentRegion = th; hasScannedForEncodings = 0; knownRegions = (th, en, Base); mainGroup = D00000000000000000000001; productRefGroup = D00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (F00000000000000000000001, F00000000000000000000002); };
};
rootObject = 200000000000000000000001;
}
"@
$projectText = $projectText.Replace('com.example.LinkAffTests','com.simplelifesolution.affiliatehelper.tests').Replace('com.example.LinkAff','com.simplelifesolution.affiliatehelper')
$projectText = $projectText.Replace('INFOPLIST_KEY_CFBundleDisplayName = LinkAff;', 'INFOPLIST_KEY_CFBundleDisplayName = "Affiliate Link Helper"; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;')
[System.IO.File]::WriteAllText((Join-Path $projectDirectory 'project.pbxproj'), $projectText, [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated LinkAff.xcodeproj"
