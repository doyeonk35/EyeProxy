#!/bin/bash
# Design/*.svg → EyeProxy/Assets.xcassets PNG + Contents.json. 산출물은 커밋한다(빌드마다 돌리지 않음).
# macOS 내장 도구(qlmanage, sips)만 쓴다. 다시 돌려도 같은 결과를 덮어쓴다.
set -euo pipefail

cd "$(dirname "$0")/.."

DESIGN="Design"
ASSETS="EyeProxy/Assets.xcassets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <svg> <px> <dest.png>
render() {
    local svg="$1" px="$2" dest="$3" out="$TMP/$2"
    mkdir -p "$out"
    qlmanage -t -s "$px" -o "$out" "$svg" >/dev/null 2>&1 || true
    local png="$out/$(basename "$svg").png"
    [[ -f "$png" ]] || { echo "error: qlmanage가 $svg ($px px)를 만들지 못함" >&2; exit 1; }
    mv "$png" "$dest"
}

# --- 앱 아이콘 ---
ICONSET="$ASSETS/AppIcon.appiconset"
mkdir -p "$ICONSET"
CHECKS=()
images=""
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        suffix=""; [[ $scale == 2 ]] && suffix="@2x"
        name="icon_${size}${suffix}.png"
        # 16·32px는 혀·패킷이 뭉개지므로 단순판을 쓴다
        svg="$DESIGN/AppIcon.svg"; (( px <= 32 )) && svg="$DESIGN/AppIcon-small.svg"
        render "$svg" "$px" "$ICONSET/$name"
        CHECKS+=("$ICONSET/$name:${px}x${px}")
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
# qlmanage는 흰 배경 정사각형 썸네일을 만들므로(템플릿이 통째로 칠해진다) 상태 막대는 sips로 그린다.
# sips(CoreSVG)는 <mask>를 잘못 그리므로 원본의 구멍은 evenodd 경로로 둔다.
for state in Open Closed Stopped; do
    set_dir="$ASSETS/MenuBarEyes$state.imageset"
    base="$(echo "$state" | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$set_dir"
    sips -s format png -z 18 22 "$DESIGN/MenuBar-Eyes-$state.svg" --out "$set_dir/$base.png" >/dev/null
    sips -s format png -z 36 44 "$DESIGN/MenuBar-Eyes-$state.svg" --out "$set_dir/$base@2x.png" >/dev/null
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
exit "$fail"
