param([string]$OutputDir = "release")
 
$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
 
Write-Host ""
Write-Host "DSCourier Build"
Write-Host ""
 
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Write-Host "[!] .NET SDK not found"; exit 1 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "[!] Git not found"; exit 1 }
 
$wingetPkg = Get-AppxPackage *DesktopAppInstaller* -ErrorAction SilentlyContinue
if (-not $wingetPkg) { Write-Host "[!] WinGet not found"; exit 1 }
$wingetPath = $wingetPkg.InstallLocation
 
$configWinmd = Join-Path $wingetPath "Microsoft.Management.Configuration.winmd"
if (-not (Test-Path $configWinmd)) { Write-Host "[!] Configuration.winmd not found, update WinGet"; exit 1 }
 
$srcCsproj = Get-ChildItem $root -Recurse -Filter "DSCourier.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $srcCsproj) { Write-Host "[!] DSCourier.csproj not found"; exit 1 }
 
Write-Host "[+] .NET $(dotnet --version) | WinGet v$($wingetPkg.Version)"
 
$interopDir = Join-Path $root "WinGet-API-from-CSharp"
if (-not (Test-Path (Join-Path $interopDir ".git"))) {
    if (Test-Path $interopDir) { Remove-Item $interopDir -Recurse -Force }
    $env:GIT_TERMINAL_PROMPT = "0"
    git clone --quiet https://github.com/marticliment/WinGet-API-from-CSharp.git $interopDir 2>$null
    if (-not (Test-Path (Join-Path $interopDir ".git"))) { Write-Host "[!] Clone failed"; exit 1 }
    Write-Host "[+] Cloned interop"
} else {
    Write-Host "[+] Interop already cloned"
}
 
$csprojPath = Join-Path $interopDir "WindowsPackageManager Interop\WindowsPackageManager Interop.csproj"
$csprojContent = Get-Content $csprojPath -Raw
 
if ($csprojContent -notmatch 'Microsoft\.Management\.Configuration') {
    $patchedCsproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0-windows10.0.22621.0</TargetFramework>
    <TargetPlatformMinVersion>10.0.22621.0</TargetPlatformMinVersion>
    <SupportedOSPlatformVersion>10.0.22621.0</SupportedOSPlatformVersion>
    <RootNamespace>DevHome.SetupFlow.Common</RootNamespace>
    <Platforms>x86;x64;arm64</Platforms>
    <RuntimeIdentifiers>win-x86;win-x64;win-arm64</RuntimeIdentifiers>
    <Nullable>disable</Nullable>
  </PropertyGroup>
  <PropertyGroup>
    <CsWinRTWindowsMetadata>10.0.22621.0</CsWinRTWindowsMetadata>
    <CsWinRTIncludes>Microsoft.Management.Deployment;Microsoft.Management.Configuration</CsWinRTIncludes>
  </PropertyGroup>
  <ItemGroup>
    <CsWinRTInputs Include="`$(TargetDir)\Microsoft.Management.Deployment.winmd" />
    <CsWinRTInputs Include="`$(TargetDir)\Microsoft.Management.Configuration.winmd" />
    <Content Include="`$(TargetDir)\Microsoft.Management.Deployment.winmd" Link="Microsoft.Management.Deployment.winmd" CopyToOutputDirectory="PreserveNewest" />
    <Content Include="`$(TargetDir)\Microsoft.Management.Configuration.winmd" Link="Microsoft.Management.Configuration.winmd" CopyToOutputDirectory="PreserveNewest" />
    <Content Include="`$(TargetDir)\winrtact.dll" Link="winrtact.dll" CopyToOutputDirectory="PreserveNewest" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Windows.CsWinRT" Version="2.0.4" />
    <PackageReference Include="Microsoft.Windows.CsWin32" Version="0.3.49-beta">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
    <PackageReference Include="Microsoft.WindowsPackageManager.ComInterop" Version="1.5.1572">
      <NoWarn>NU1701</NoWarn>
      <GeneratePathProperty>true</GeneratePathProperty>
      <IncludeAssets>none</IncludeAssets>
    </PackageReference>
  </ItemGroup>
  <Target Name="CopyWinmdToTargetDir" BeforeTargets="BeforeBuild">
    <Copy SourceFiles="`$(PkgMicrosoft_WindowsPackageManager_ComInterop)\lib\Microsoft.Management.Deployment.winmd" DestinationFolder="`$(TargetDir)" />
    <Copy SourceFiles="$configWinmd" DestinationFolder="`$(TargetDir)" />
    <Copy SourceFiles="`$(PkgMicrosoft_WindowsPackageManager_ComInterop)\runtimes\win10-`$(Platform)\native\winrtact.dll" DestinationFolder="`$(TargetDir)" />
  </Target>
</Project>
"@
    [System.IO.File]::WriteAllText($csprojPath, $patchedCsproj, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[+] Patched interop csproj"
} else {
    Write-Host "[+] Interop csproj already patched"
}
 
$classDefPath = Join-Path $interopDir "WindowsPackageManager Interop\WindowsPackageManager\ClassesDefinition.cs"
$classDefContent = Get-Content $classDefPath -Raw
 
if ($classDefContent -notmatch 'ConfigurationStaticFunctions') {
    $patchedClassDef = @'
using System;
using System.Collections.Generic;
using Microsoft.Management.Deployment;
using Microsoft.Management.Configuration;
 
namespace WindowsPackageManager.Interop;
 
internal static class ClassesDefinition
{
    private static Dictionary<Type, ClassModel> Classes { get; } = new()
    {
        [typeof(PackageManager)] = new()
        {
            ProjectedClassType = typeof(PackageManager),
            InterfaceType = typeof(IPackageManager),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("C53A4F16-787E-42A4-B304-29EFFB4BF597"),
                [ClsidContext.Dev] = new Guid("74CB3139-B7C5-4B9E-9388-E6616DEA288C"),
            },
        },
        [typeof(FindPackagesOptions)] = new()
        {
            ProjectedClassType = typeof(FindPackagesOptions),
            InterfaceType = typeof(IFindPackagesOptions),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("572DED96-9C60-4526-8F92-EE7D91D38C1A"),
                [ClsidContext.Dev] = new Guid("1BD8FF3A-EC50-4F69-AEEE-DF4C9D3BAA96"),
            },
        },
        [typeof(CreateCompositePackageCatalogOptions)] = new()
        {
            ProjectedClassType = typeof(CreateCompositePackageCatalogOptions),
            InterfaceType = typeof(ICreateCompositePackageCatalogOptions),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("526534B8-7E46-47C8-8416-B1685C327D37"),
                [ClsidContext.Dev] = new Guid("EE160901-B317-4EA7-9CC6-5355C6D7D8A7"),
            },
        },
        [typeof(InstallOptions)] = new()
        {
            ProjectedClassType = typeof(InstallOptions),
            InterfaceType = typeof(IInstallOptions),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("1095F097-EB96-453B-B4E6-1613637F3B14"),
                [ClsidContext.Dev] = new Guid("44FE0580-62F7-44D4-9E91-AA9614AB3E86"),
            },
        },
        [typeof(UninstallOptions)] = new()
        {
            ProjectedClassType = typeof(UninstallOptions),
            InterfaceType = typeof(IUninstallOptions),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("E1D9A11E-9F85-4D87-9C17-2B93143ADB8D"),
                [ClsidContext.Dev] = new Guid("AA2A5C04-1AD9-46C4-B74F-6B334AD7EB8C"),
            },
        },
        [typeof(PackageMatchFilter)] = new()
        {
            ProjectedClassType = typeof(PackageMatchFilter),
            InterfaceType = typeof(IPackageMatchFilter),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("D02C9DAF-99DC-429C-B503-4E504E4AB000"),
                [ClsidContext.Dev] = new Guid("3F85B9F4-487A-4C48-9035-2903F8A6D9E8"),
            },
        },
        [typeof(ConfigurationStaticFunctions)] = new()
        {
            ProjectedClassType = typeof(ConfigurationStaticFunctions),
            InterfaceType = typeof(IConfigurationStatics),
            Clsids = new Dictionary<ClsidContext, Guid>()
            {
                [ClsidContext.Prod] = new Guid("73D763B7-2937-432F-A97A-D98A4A596126"),
                [ClsidContext.Dev] = new Guid("73D763B7-2937-432F-A97A-D98A4A596126"),
            },
        },
    };
 
    public static Guid GetClsid<T>(ClsidContext context)
    {
        ValidateType<T>();
        return Classes[typeof(T)].GetClsid(context);
    }
 
    public static Guid GetIid<T>()
    {
        ValidateType<T>();
        return Classes[typeof(T)].GetIid();
    }
 
    private static void ValidateType<TType>()
    {
        if (!Classes.ContainsKey(typeof(TType)))
        {
            throw new InvalidOperationException($"{typeof(TType).Name} is not a projected class type.");
        }
    }
}
'@
    [System.IO.File]::WriteAllText($classDefPath, $patchedClassDef, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[+] Patched ClassesDefinition.cs"
} else {
    Write-Host "[+] ClassesDefinition.cs already patched"
}
 
$factoryPath = Join-Path $interopDir "WindowsPackageManager Interop\WindowsPackageManager\WindowsPackageManagerFactory.cs"
$factoryContent = Get-Content $factoryPath -Raw
 
if ($factoryContent -notmatch 'CreateConfigurationStaticFunctions') {
    $patchedFactory = @'
using System;
using Microsoft.Management.Deployment;
using Microsoft.Management.Configuration;
 
namespace WindowsPackageManager.Interop;
 
public abstract class WindowsPackageManagerFactory
{
    private readonly ClsidContext _clsidContext;
 
    public WindowsPackageManagerFactory(ClsidContext clsidContext)
    {
        _clsidContext = clsidContext;
    }
 
    protected abstract T CreateInstance<T>(Guid clsid, Guid iid);
 
    public PackageManager CreatePackageManager() => CreateInstance<PackageManager>();
    public FindPackagesOptions CreateFindPackagesOptions() => CreateInstance<FindPackagesOptions>();
    public CreateCompositePackageCatalogOptions CreateCreateCompositePackageCatalogOptions() => CreateInstance<CreateCompositePackageCatalogOptions>();
    public InstallOptions CreateInstallOptions() => CreateInstance<InstallOptions>();
    public UninstallOptions CreateUninstallOptions() => CreateInstance<UninstallOptions>();
    public PackageMatchFilter CreatePackageMatchFilter() => CreateInstance<PackageMatchFilter>();
    public ConfigurationStaticFunctions CreateConfigurationStaticFunctions() => CreateInstance<ConfigurationStaticFunctions>();
 
    private T CreateInstance<T>()
    {
        var clsid = ClassesDefinition.GetClsid<T>(_clsidContext);
        var iid = ClassesDefinition.GetIid<T>();
        return CreateInstance<T>(clsid, iid);
    }
}
'@
    [System.IO.File]::WriteAllText($factoryPath, $patchedFactory, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[+] Patched Factory"
} else {
    Write-Host "[+] Factory already patched"
}
 
Write-Host "[*] Building interop..."
Push-Location $interopDir
$buildOutput = & dotnet build "WindowsPackageManager Interop\WindowsPackageManager Interop.csproj" -p:Platform=x64 2>&1 | Out-String
Pop-Location
 
if ($buildOutput -notmatch 'Build succeeded') {
    $errors = ($buildOutput -split "`n") | Where-Object { $_ -match ': error ' }
    if ($errors) {
        Write-Host "[!] Interop build failed:"
        $errors | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
}
Write-Host "[+] Interop built"
 
$interopProjDir = Join-Path $interopDir "WindowsPackageManager Interop"
$interopDll = Get-ChildItem $interopProjDir -Recurse -Filter "WindowsPackageManager Interop.dll" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'bin' } | Select-Object -First 1
if (-not $interopDll) { Write-Host "[!] Interop DLL not found"; exit 1 }
$interopBinDir = $interopDll.DirectoryName
 
Write-Host "[*] Building DSCourier..."
$srcDir = $srcCsproj.DirectoryName
$originalCsproj = Get-Content $srcCsproj.FullName -Raw
 
$clientCsproj = $originalCsproj
$clientCsproj = $clientCsproj -replace '<HintPath>[^<]+</HintPath>', "<HintPath>$($interopDll.FullName)</HintPath>"
[System.IO.File]::WriteAllText($srcCsproj.FullName, $clientCsproj, [System.Text.UTF8Encoding]::new($false))
 
Push-Location $srcDir
Remove-Item ".\bin" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ".\obj" -Recurse -Force -ErrorAction SilentlyContinue
& dotnet build -c Release 2>&1 | Out-Null
Pop-Location
 
$exeName = "DSCourier.exe"
$asmMatch = [regex]::Match($clientCsproj, '<AssemblyName>([^<]+)</AssemblyName>')
if ($asmMatch.Success) { $exeName = "$($asmMatch.Groups[1].Value).exe" }
$asmName = $exeName -replace '\.exe$', ''
 
$builtExe = Get-ChildItem $srcDir -Recurse -Filter $exeName -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'bin' } | Select-Object -First 1
if (-not $builtExe) { Write-Host "[!] $exeName not found"; exit 1 }
$exeBinDir = $builtExe.DirectoryName
Write-Host "[+] DSCourier built"
 
Write-Host "[*] Trimming SDK..."
 
$trimmerRoots = @'
<linker>
  <assembly fullname="Microsoft.Windows.SDK.NET">
    <type fullname="System.IO.WindowsRuntimeStreamExtensions" preserve="all" />
    <type fullname="Windows.Storage.Streams.*" preserve="all" />
    <type fullname="System.Runtime.InteropServices.WindowsRuntime.*" preserve="all" />
  </assembly>
</linker>
'@
$trimmerPath = Join-Path $srcDir "TrimmerRoots.xml"
[System.IO.File]::WriteAllText($trimmerPath, $trimmerRoots, [System.Text.UTF8Encoding]::new($false))
 
$trimCsproj = Get-Content $srcCsproj.FullName -Raw
$trimCsproj = $trimCsproj -replace '</PropertyGroup>', "  <PublishTrimmed>true</PublishTrimmed>`n    <SelfContained>true</SelfContained>`n    <TrimMode>link</TrimMode>`n  </PropertyGroup>"
if ($trimCsproj -notmatch 'TrimmerRootDescriptor') {
    $trimCsproj = $trimCsproj -replace '</Project>', "  <ItemGroup>`n    <TrimmerRootDescriptor Include=`"TrimmerRoots.xml`" />`n  </ItemGroup>`n</Project>"
}
[System.IO.File]::WriteAllText($srcCsproj.FullName, $trimCsproj, [System.Text.UTF8Encoding]::new($false))
 
Push-Location $srcDir
Remove-Item ".\bin" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ".\obj" -Recurse -Force -ErrorAction SilentlyContinue
& dotnet publish -c Release 2>&1 | Out-Null
Pop-Location
 
$trimmedSdk = Get-ChildItem $srcDir -Recurse -Filter "Microsoft.Windows.SDK.NET.dll" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'publish' -and $_.Length -lt 1MB } | Select-Object -First 1
 
$trimmedSdkPath = $null
if ($trimmedSdk) {
    $trimmedSdkPath = Join-Path $root "trimmed-sdk.dll"
    Copy-Item $trimmedSdk.FullName -Destination $trimmedSdkPath -Force
    $kb = [math]::Round($trimmedSdk.Length / 1KB, 1)
    Write-Host "[+] Trimmed SDK: $kb KB"
} else {
    Write-Host "[!] Trim failed, using full SDK"
}
 
[System.IO.File]::WriteAllText($srcCsproj.FullName, $clientCsproj, [System.Text.UTF8Encoding]::new($false))
 
Push-Location $srcDir
Remove-Item ".\bin" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ".\obj" -Recurse -Force -ErrorAction SilentlyContinue
& dotnet build -c Release 2>&1 | Out-Null
Pop-Location
 
$builtExe = Get-ChildItem $srcDir -Recurse -Filter $exeName -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'bin' } | Select-Object -First 1
$exeBinDir = $builtExe.DirectoryName
 
Write-Host "[*] Assembling release..."
 
$releaseDir = Join-Path $root $OutputDir
if (Test-Path $releaseDir) { Remove-Item $releaseDir -Recurse -Force }
New-Item -Path $releaseDir -ItemType Directory -Force | Out-Null
 
foreach ($f in @("$exeName", "$asmName.dll", "$asmName.runtimeconfig.json")) {
    $src = Join-Path $exeBinDir $f
    if (Test-Path $src) { Copy-Item $src -Destination $releaseDir -Force; Write-Host "  [+] $f" }
}
 
foreach ($f in @("WindowsPackageManager Interop.dll", "winrtact.dll", "WinRT.Runtime.dll", "Microsoft.Windows.SDK.NET.dll", "Microsoft.Management.Configuration.winmd", "Microsoft.Management.Deployment.winmd")) {
    $src = Join-Path $interopBinDir $f
    if (-not (Test-Path $src)) { $src = Join-Path $exeBinDir $f }
    if (Test-Path $src) { Copy-Item $src -Destination $releaseDir -Force; Write-Host "  [+] $f" }
    else { Write-Host "  [!] Missing: $f" }
}
 
if ($trimmedSdkPath -and (Test-Path $trimmedSdkPath)) {
    Copy-Item $trimmedSdkPath -Destination (Join-Path $releaseDir "Microsoft.Windows.SDK.NET.dll") -Force
    Remove-Item $trimmedSdkPath -Force
    Write-Host "  [+] Swapped in trimmed SDK"
}
 
Write-Host ""
Write-Host "Build complete: $releaseDir"
Write-Host ""
$totalSize = 0
Get-ChildItem $releaseDir -File | ForEach-Object {
    $kb = [math]::Round($_.Length / 1KB, 1)
    $totalSize += $_.Length
    Write-Host "  $($_.Name)  ($kb KB)"
}
Write-Host ""
$totalMb = [math]::Round($totalSize / 1MB, 2)
Write-Host "  Total: $totalMb MB"
Write-Host ""