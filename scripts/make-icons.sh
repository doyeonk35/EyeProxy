#!/bin/bash
# Design/*.svg → EyeProxy/Assets.xcassets PNG + Contents.json. 산출물은 커밋한다(빌드마다 돌리지 않음).
# macOS 내장 도구(sips)와 Xcode의 swift만 쓴다. 다시 돌려도 같은 결과를 덮어쓴다.
# qlmanage는 흰 배경 정사각형 썸네일을 만들어(투명 없음) 쓰지 않는다.
# sips(CoreSVG)는 <mask>를 잘못 그리므로 원본의 구멍은 evenodd 경로로 둔다(clipPath·linearGradient는 괜찮다).
set -euo pipefail

cd "$(dirname "$0")/.."

DESIGN="Design"
ASSETS="EyeProxy/Assets.xcassets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <svg> <height px> <width px> <dest.png>
render() {
    sips -s format png -z "$2" "$3" "$1" --out "$4" >/dev/null
}

# --- 앱 아이콘 ---
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET"
CHECKS=()
APPICONS=()
images=""
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        suffix=""; [[ $scale == 2 ]] && suffix="@2x"
        name="icon_${size}${suffix}.png"
        # 16·32px는 혀·패킷이 뭉개지므로 단순판을 쓴다
        svg="$DESIGN/AppIcon.svg"; (( px <= 32 )) && svg="$DESIGN/AppIcon-small.svg"
        render "$svg" "$px" "$px" "$ICONSET/$name"
        CHECKS+=("$ICONSET/$name:${px}x${px}")
        APPICONS+=("$ICONSET/$name")
        images+="${images:+,}
    {\"filename\":\"$name\",\"idiom\":\"mac\",\"scale\":\"${scale}x\",\"size\":\"${size}x${size}\"}"
    done
done
cat > "$ICONSET/Contents.json" <<EOF
{
  "images":[$images
  ],
  "info":{"author":"xcode","version":1}
}
EOF

# --- 상태 막대 템플릿 (22×18pt) ---
for state in Open Closed Stopped; do
    set_dir="$ASSETS/MenuBarEyes$state.imageset"
    base="$(echo "$state" | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$set_dir"
    render "$DESIGN/MenuBar-Eyes-$state.svg" 18 22 "$set_dir/$base.png"
    render "$DESIGN/MenuBar-Eyes-$state.svg" 36 44 "$set_dir/$base@2x.png"
    CHECKS+=("$set_dir/$base.png:22x18" "$set_dir/$base@2x.png:44x36")
    cat > "$set_dir/Contents.json" <<EOF
{
  "images":[
    {"filename":"$base.png","idiom":"universal","scale":"1x"},
    {"filename":"$base@2x.png","idiom":"universal","scale":"2x"}
  ],
  "info":{"author":"xcode","version":1},
  "properties":{"template-rendering-intent":"template"}
}
EOF
done

# --- 크기 검증 ---
fail=0
for check in "${CHECKS[@]}"; do
    file="${check%:*}" want="${check##*:}"
    w="$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')"
    h="$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')"
    if [[ "${w}x${h}" == "$want" ]]; then
        echo "ok   ${w}x${h}  $file"
    else
        echo "FAIL ${w}x${h} (want ${want})  $file" >&2
        fail=1
    fi
done

# --- 앱 아이콘 네 모서리 투명 검증 ---
# sips로는 픽셀 알파를 읽을 수 없어서 AppKit을 쓰는 몇 줄짜리 Swift를 xcrun swift로 돌린다(Xcode 기본 포함).
cat > "$TMP/corners.swift" <<'EOF'
import AppKit
var bad = false
for path in CommandLine.arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data), rep.hasAlpha else {
        print("FAIL 알파 없음  \(path)"); bad = true; continue
    }
    let alphaIndex = rep.bitmapFormat.contains(.alphaFirst) ? 0 : rep.samplesPerPixel - 1
    let w = rep.pixelsWide - 1, h = rep.pixelsHigh - 1
    let alphas = [(0, 0), (w, 0), (0, h), (w, h)].map { x, y in
        var p = [Int](repeating: 0, count: rep.samplesPerPixel)
        rep.getPixel(&p, atX: x, y: y)
        return p[alphaIndex]
    }
    if alphas.allSatisfy({ $0 == 0 }) { print("ok   모서리 투명  \(path)") } else { print("FAIL 모서리 알파 \(alphas)  \(path)"); bad = true }
}
exit(bad ? 1 : 0)
EOF
xcrun swift "$TMP/corners.swift" "${APPICONS[@]}" || fail=1
exit "$fail"
