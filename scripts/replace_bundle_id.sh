#!/bin/bash

# Flutter Bundle ID 替换脚本
# 用法: ./replace_bundle_id.sh <new_bundle_id>
# 例如: ./replace_bundle_id.sh site.ltot.toy

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查参数
if [ $# -eq 0 ]; then
    print_error "请提供新的 Bundle ID"
    echo "用法: $0 <new_bundle_id>"
    echo "例如: $0 site.ltot.toy"
    exit 1
fi

NEW_BUNDLE_ID="$1"

# 验证 Bundle ID 格式
if [[ ! $NEW_BUNDLE_ID =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$ ]]; then
    print_error "Bundle ID 格式无效: $NEW_BUNDLE_ID"
    print_error "正确格式应该是: com.example.app 或 site.ltot.toy"
    exit 1
fi

# 检查是否在 Flutter 项目根目录
if [ ! -f "pubspec.yaml" ]; then
    print_error "请在 Flutter 项目根目录下运行此脚本"
    exit 1
fi

# 提取项目名称（Bundle ID 的最后一部分）
NEW_PROJECT_NAME=$(echo "$NEW_BUNDLE_ID" | awk -F'.' '{print $NF}')
print_info "新项目名称: $NEW_PROJECT_NAME"
print_info "新 Bundle ID: $NEW_BUNDLE_ID"

# 获取当前的项目信息
CURRENT_PROJECT_NAME=$(grep "^name:" pubspec.yaml | awk '{print $2}' | tr -d '"' | tr -d "'")
CURRENT_ANDROID_ID=$(grep "applicationId" android/app/build.gradle | head -1 | awk -F'"' '{print $2}' 2>/dev/null || echo "")
CURRENT_IOS_ID=""

if [ -f "ios/Runner/Info.plist" ]; then
    CURRENT_IOS_ID=$(plutil -extract CFBundleIdentifier raw ios/Runner/Info.plist 2>/dev/null || \
                    grep -A 1 "CFBundleIdentifier" ios/Runner/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/' 2>/dev/null || echo "")
fi

print_info "当前项目名称: $CURRENT_PROJECT_NAME"
print_info "当前 Android ID: ${CURRENT_ANDROID_ID:-'未找到'}"
print_info "当前 iOS ID: ${CURRENT_IOS_ID:-'未找到'}"

# 确认操作
echo
print_warning "即将进行以下更改:"
echo "  - 项目名称: $CURRENT_PROJECT_NAME → $NEW_PROJECT_NAME"
echo "  - Bundle ID: → $NEW_BUNDLE_ID"
echo "  - 更新所有 Dart 文件中的 package 引用"
echo "  - 更新 Android 配置和文件路径"
echo "  - 更新 iOS 配置"
echo
read -p "是否继续? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "操作已取消"
    exit 0
fi

# 创建备份
BACKUP_DIR="bundle_id_backup_$(date +%Y%m%d_%H%M%S)"
print_info "创建备份到: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -r pubspec.yaml android ios lib test "$BACKUP_DIR/" 2>/dev/null || true

# 1. 更新 pubspec.yaml
print_info "更新 pubspec.yaml..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^name: .*/name: $NEW_PROJECT_NAME/" pubspec.yaml
else
    # Linux
    sed -i "s/^name: .*/name: $NEW_PROJECT_NAME/" pubspec.yaml
fi
print_success "pubspec.yaml 已更新"

# 2. 更新 Dart 文件中的 package 引用
print_info "更新 Dart 文件中的 package 引用..."

# 查找所有 Dart 文件并替换 package 引用
find lib test -name "*.dart" -type f 2>/dev/null | while read -r file; do
    if grep -q "package:$CURRENT_PROJECT_NAME/" "$file" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/package:$CURRENT_PROJECT_NAME\//package:$NEW_PROJECT_NAME\//g" "$file"
        else
            sed -i "s/package:$CURRENT_PROJECT_NAME\//package:$NEW_PROJECT_NAME\//g" "$file"
        fi
        print_info "  更新: $file"
    fi
done
print_success "Dart 文件 package 引用已更新"

# 3. 更新 Android 配置
print_info "更新 Android 配置..."

# 更新 applicationId
if [ -f "android/app/build.gradle" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/applicationId .*/applicationId \"$NEW_BUNDLE_ID\"/" android/app/build.gradle
    else
        sed -i "s/applicationId .*/applicationId \"$NEW_BUNDLE_ID\"/" android/app/build.gradle
    fi
    print_success "  build.gradle applicationId 已更新"
fi

# 更新 namespace
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/namespace .*/namespace \"$NEW_BUNDLE_ID\"/" android/app/build.gradle
else
    sed -i "s/namespace .*/namespace \"$NEW_BUNDLE_ID\"/" android/app/build.gradle
fi

# 更新 Android 包路径
if [ ! -z "$CURRENT_ANDROID_ID" ] && [ "$CURRENT_ANDROID_ID" != "$NEW_BUNDLE_ID" ]; then
    # 转换包路径
    OLD_PACKAGE_PATH=$(echo "$CURRENT_ANDROID_ID" | tr '.' '/')
    NEW_PACKAGE_PATH=$(echo "$NEW_BUNDLE_ID" | tr '.' '/')
    
    # 处理Java目录
    ANDROID_MAIN_JAVA_PATH="android/app/src/main/java"
    OLD_JAVA_FULL_PATH="$ANDROID_MAIN_JAVA_PATH/$OLD_PACKAGE_PATH"
    NEW_JAVA_FULL_PATH="$ANDROID_MAIN_JAVA_PATH/$NEW_PACKAGE_PATH"
    
    if [ -d "$OLD_JAVA_FULL_PATH" ]; then
        print_info "  移动 Android Java包目录: $OLD_JAVA_FULL_PATH → $NEW_JAVA_FULL_PATH"
        
        # 创建新的目录结构
        mkdir -p "$(dirname "$NEW_JAVA_FULL_PATH")"
        
        # 移动文件
        mv "$OLD_JAVA_FULL_PATH" "$NEW_JAVA_FULL_PATH"
        
        # 清理空的旧目录
        find "$ANDROID_MAIN_JAVA_PATH" -type d -empty -delete 2>/dev/null || true
        
        print_success "  Android Java包目录已移动"
    fi
    
    # 处理Kotlin目录
    ANDROID_MAIN_KOTLIN_PATH="android/app/src/main/kotlin"
    OLD_KOTLIN_FULL_PATH="$ANDROID_MAIN_KOTLIN_PATH/$OLD_PACKAGE_PATH"
    NEW_KOTLIN_FULL_PATH="$ANDROID_MAIN_KOTLIN_PATH/$NEW_PACKAGE_PATH"
    
    if [ -d "$OLD_KOTLIN_FULL_PATH" ]; then
        print_info "  移动 Android Kotlin包目录: $OLD_KOTLIN_FULL_PATH → $NEW_KOTLIN_FULL_PATH"
        
        # 创建新的目录结构
        mkdir -p "$(dirname "$NEW_KOTLIN_FULL_PATH")"
        
        # 移动文件
        mv "$OLD_KOTLIN_FULL_PATH" "$NEW_KOTLIN_FULL_PATH"
        
        # 清理空的旧目录
        find "$ANDROID_MAIN_KOTLIN_PATH" -type d -empty -delete 2>/dev/null || true
        
        print_success "  Android Kotlin包目录已移动"
    fi
    
    # 更新 MainActivity.java/kt 中的 package 声明
    find "$NEW_JAVA_FULL_PATH" "$NEW_KOTLIN_FULL_PATH" -name "*.kt" -type f 2>/dev/null | while read -r file; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^package .*/package $NEW_BUNDLE_ID/" "$file"
        else
            sed -i "s/^package .*/package $NEW_BUNDLE_ID/" "$file"
        fi
        print_info "    更新: $file"
    done
fi

# 更新 AndroidManifest.xml
find android -name "AndroidManifest.xml" -type f | while read -r manifest; do
    if grep -q "package=" "$manifest" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/package=\"[^\"]*\"/package=\"$NEW_BUNDLE_ID\"/" "$manifest"
        else
            sed -i "s/package=\"[^\"]*\"/package=\"$NEW_BUNDLE_ID\"/" "$manifest"
        fi
        print_info "  更新: $manifest"
    fi
done

print_success "Android 配置已更新"

# 4. 更新 iOS 配置
print_info "更新 iOS 配置..."

if [ -f "ios/Runner/Info.plist" ]; then
    # 使用 plutil 更新 (macOS)
    if command -v plutil >/dev/null 2>&1; then
        plutil -replace CFBundleIdentifier -string "$NEW_BUNDLE_ID" ios/Runner/Info.plist 2>/dev/null || {
            # 如果 plutil 失败，使用 sed
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "/<key>CFBundleIdentifier<\/key>/,/<string>.*<\/string>/ s/<string>.*<\/string>/<string>$NEW_BUNDLE_ID<\/string>/" ios/Runner/Info.plist
            else
                sed -i "/<key>CFBundleIdentifier<\/key>/,/<string>.*<\/string>/ s/<string>.*<\/string>/<string>$NEW_BUNDLE_ID<\/string>/" ios/Runner/Info.plist
            fi
        }
    else
        # 使用 sed 更新
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/<key>CFBundleIdentifier<\/key>/,/<string>.*<\/string>/ s/<string>.*<\/string>/<string>$NEW_BUNDLE_ID<\/string>/" ios/Runner/Info.plist
        else
            sed -i "/<key>CFBundleIdentifier<\/key>/,/<string>.*<\/string>/ s/<string>.*<\/string>/<string>$NEW_BUNDLE_ID<\/string>/" ios/Runner/Info.plist
        fi
    fi
    print_success "  Info.plist 已更新"
fi

# 更新 project.pbxproj
if [ -f "ios/Runner.xcodeproj/project.pbxproj" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $NEW_BUNDLE_ID;/" ios/Runner.xcodeproj/project.pbxproj
    else
        sed -i "s/PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $NEW_BUNDLE_ID;/" ios/Runner.xcodeproj/project.pbxproj
    fi
    print_success "  project.pbxproj 已更新"
fi

print_success "iOS 配置已更新"

# 5. 更新其他可能的配置文件
print_info "检查其他配置文件..."

# 更新 .metadata 文件（如果存在）
if [ -f ".metadata" ]; then
    if grep -q "project_name:" ".metadata" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/project_name: .*/project_name: $NEW_PROJECT_NAME/" .metadata
        else
            sed -i "s/project_name: .*/project_name: $NEW_PROJECT_NAME/" .metadata
        fi
        print_success "  .metadata 已更新"
    fi
fi

# 更新 README.md 中的项目名称（如果存在）
if [ -f "README.md" ]; then
    if grep -q "$CURRENT_PROJECT_NAME" "README.md" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/$CURRENT_PROJECT_NAME/$NEW_PROJECT_NAME/g" README.md
        else
            sed -i "s/$CURRENT_PROJECT_NAME/$NEW_PROJECT_NAME/g" README.md
        fi
        print_success "  README.md 已更新"
    fi
fi

# 6. 清理和重新生成
print_info "清理项目..."
flutter clean >/dev/null 2>&1 || true

print_info "获取依赖..."
flutter pub get >/dev/null 2>&1 || {
    print_warning "flutter pub get 失败，请手动运行"
}

# 7. 验证更改
print_info "验证更改..."
echo
echo "=== 更改后的配置 ==="
echo "项目名称: $(grep '^name:' pubspec.yaml | awk '{print $2}')"
echo "Android ID: $(grep applicationId android/app/build.gradle | head -1 | awk -F'"' '{print $2}' 2>/dev/null || echo '未找到')"
if [ -f "ios/Runner/Info.plist" ]; then
    echo "iOS Bundle ID: $(plutil -extract CFBundleIdentifier raw ios/Runner/Info.plist 2>/dev/null || \
                        grep -A 1 'CFBundleIdentifier' ios/Runner/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/' 2>/dev/null || echo '未找到')"
fi

echo
print_success "Bundle ID 替换完成！"
print_info "备份已保存到: $BACKUP_DIR"
echo
print_warning "建议执行以下操作:"
echo "  1. 运行 'flutter clean && flutter pub get'"
echo "  2. 测试应用是否正常编译和运行"
echo "  3. 检查所有 import 语句是否正确"
echo "  4. 如果有问题，可以从备份恢复: cp -r $BACKUP_DIR/* ."
echo "  5. 撤销操作: git restore lib android/ ios/ pubspec.yaml test/ README.md"
echo
print_info "完成！"