# 🏗️ Building Lantern

## ⚠️ 重要说明 / Important Note

**必须在原生终端中构建。** DSH Web 沙盒环境无法编译 Swift，因为 CLT27 clang 硬编码了 ModuleCache 路径 (`/var/folders/.../C/clang/ModuleCache/`)，而沙盒禁止对该路径进行任何写入操作（包括修改现有文件）。

**You MUST build in a native terminal.** The DSH web sandbox cannot compile Swift due to a hardcoded ModuleCache path restriction that blocks ALL writes under `/var/folders/`.

---

## 快速构建 / Quick Build

```bash
cd /Users/jindy/Archive/WorkBuddy/Lantern
bash build.sh all
open Lantern-*.dmg
```

这将执行完整流程：clean → build → sign → dmg。

This runs the full pipeline: clean → build → sign → DMG.

---

## 分步构建 / Step-by-step Build

```bash
# 1. 清理旧构建 / Clean previous builds
bash build.sh clean

# 2. 编译 Release 版本 / Compile Release binary
bash build.sh release
# Output: .build/release/Lantern.app (~150MB)

# 3. 代码签名 / Code sign (可选 / optional for local testing)
bash build.sh sign

# 4. 创建 DMG / Create DMG installer
bash build.sh dmg
# Output: Lantern-unknown.dmg

# 5. 运行应用 / Run the app
open .build/release/Lantern.app
```

---

## 故障排除 / Troubleshooting

### 错误：`Operation not permitted` on ModuleCache
如果在 DSH 界面中看到此错误，请切换到原生终端执行上述命令。

If you see this error in the DSH interface, switch to your native terminal.

### 需要 Xcode Command Line Tools
确保已安装且版本兼容：
```bash
xcode-select --version
swift --version  # Should show 6.4.2 or later
```

Requires Xcode Command Line Tools (CLT) version compatible with Swift 6.4.2.

### DMG 未自动打开
手动打开生成的 DMG：
```bash
open /Users/jindy/Archive/WorkBuddy/Lantern/Lantern-*.dmg
```

If the DMG doesn't open automatically, open it manually.

---

## 技术细节 / Technical Details

- **工具链 / Toolchain:** Apple Swift 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)
- **目标平台 / Target:** arm64-apple-macosx14.0
- **SDK:** macOS 27.2 SDK (/Applications/Xcode.app/...)
- **依赖 / Dependencies:** 零外部依赖 (zero external deps)
- **包管理器 / Package Manager:** Swift Package Manager (SPM)
