#[cfg(windows)]
fn build_windows() {
    let file = "src/platform/windows.cc";
    let file2 = "src/platform/windows_delete_test_cert.cc";
    cc::Build::new().file(file).file(file2).compile("windows");
    println!("cargo:rustc-link-lib=WtsApi32");
    println!("cargo:rerun-if-changed={}", file);
    println!("cargo:rerun-if-changed={}", file2);
}

#[cfg(target_os = "macos")]
fn build_mac() {
    let file = "src/platform/macos.mm";
    let mut b = cc::Build::new();
    if let Ok(os_version::OsVersion::MacOS(v)) = os_version::detect() {
        let v = v.version;
        if v.contains("10.14") {
            b.flag("-DNO_InputMonitoringAuthStatus=1");
        }
    }
    b.flag("-std=c++17").file(file).compile("macos");
    println!("cargo:rerun-if-changed={}", file);
}

#[cfg(windows)]
fn flutter_product_version() -> Option<(String, u64)> {
    let pubspec = std::fs::read_to_string("flutter/pubspec.yaml").ok()?;
    let version = pubspec
        .lines()
        .find_map(|line| line.trim().strip_prefix("version:"))?
        .trim()
        .to_owned();
    let mut version_parts = version.split('+');
    let semantic = version_parts.next()?;
    let build = version_parts.next().unwrap_or("0").parse::<u64>().ok()?;
    let numbers = semantic
        .split('.')
        .map(str::parse::<u64>)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    if numbers.len() != 3 || numbers.iter().any(|number| *number > u16::MAX as u64) {
        return None;
    }
    if build > u16::MAX as u64 {
        return None;
    }
    let packed =
        (numbers[0] << 48) | (numbers[1] << 32) | (numbers[2] << 16) | build;
    Some((version, packed))
}

#[cfg(windows)]
fn build_manifest() {
    use std::io::Write;
    let is_release = std::env::var("PROFILE").ok().as_deref() == Some("release");
    let is_flutter = std::env::var_os("CARGO_FEATURE_FLUTTER").is_some();
    let is_inline = std::env::var_os("CARGO_FEATURE_INLINE").is_some();
    if is_release && (is_flutter || is_inline) {
        let mut res = winres::WindowsResource::new();
        res.set_language(winapi::um::winnt::MAKELANGID(
            winapi::um::winnt::LANG_ENGLISH,
            winapi::um::winnt::SUBLANG_ENGLISH_US,
        ));
        if is_flutter {
            res.set("CompanyName", "SAKURA-NET Co., Ltd.")
                .set("ProductName", "SAKURA-Remote")
                .set("InternalName", "SAKURA-Remote-Core")
                .set("OriginalFilename", "SAKURA-Remote-Core.dll")
                .set(
                    "FileDescription",
                    "SAKURA-Remote Windows Core Library",
                )
                .set_version_info(winres::VersionInfo::FILETYPE, 0x2);
            if let Some((version, packed)) = flutter_product_version() {
                res.set("FileVersion", &version)
                    .set("ProductVersion", &version)
                    .set_version_info(winres::VersionInfo::FILEVERSION, packed)
                    .set_version_info(winres::VersionInfo::PRODUCTVERSION, packed);
            }
        } else {
            res.set_icon("res/icon.ico")
                .set_manifest_file("res/manifest.xml");
        }
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}

fn install_android_deps() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os != "android" {
        return;
    }
    let mut target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_arch == "x86_64" {
        target_arch = "x64".to_owned();
    } else if target_arch == "x86" {
        target_arch = "x86".to_owned();
    } else if target_arch == "aarch64" {
        target_arch = "arm64".to_owned();
    } else {
        target_arch = "arm".to_owned();
    }
    let target = format!("{}-android", target_arch);
    let vcpkg_root = std::env::var("VCPKG_ROOT").unwrap();
    let mut path: std::path::PathBuf = vcpkg_root.into();
    if let Ok(vcpkg_root) = std::env::var("VCPKG_INSTALLED_ROOT") {
        path = vcpkg_root.into();
    } else {
        path.push("installed");
    }
    path.push(target);
    println!(
        "cargo:rustc-link-search={}",
        path.join("lib").to_str().unwrap()
    );
    println!("cargo:rustc-link-lib=ndk_compat");
    println!("cargo:rustc-link-lib=oboe");
    println!("cargo:rustc-link-lib=c++");
    println!("cargo:rustc-link-lib=OpenSLES");
}

fn main() {
    hbb_common::gen_version();
    install_android_deps();
    #[cfg(windows)]
    build_manifest();
    #[cfg(windows)]
    build_windows();
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os == "macos" {
        #[cfg(target_os = "macos")]
        build_mac();
        println!("cargo:rustc-link-lib=framework=ApplicationServices");
    }
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=flutter/pubspec.yaml");
}
