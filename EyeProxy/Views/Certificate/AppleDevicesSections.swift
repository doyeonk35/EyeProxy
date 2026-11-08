import SwiftUI

/// iPhone·iPad: Wi-Fi 프록시 프로필 + 설치 안내.
struct IOSDevicesSection: View {
    var body: some View {
        Section("실기기 프로필 만들기") {
            ProfileFormView()
            Checklist(title: "iPhone·iPad") {
                Text("1. 프로필을 AirDrop·메일로 보내 설치하거나, Wi-Fi 설정에서 수동 프록시(Mac IP·포트)를 입력합니다.")
                Text("2. Safari로 http://prog/ssl 을 열어 CA 프로필을 설치하고 인증서 신뢰 설정에서 신뢰합니다.")
            }
        }
    }
}

/// Apple TV·Apple Watch: 프로필 + Apple TV 안내 + Watch 한 줄.
struct TVWatchSection: View {
    var body: some View {
        Section("실기기 프로필 만들기") {
            ProfileFormView()
            Checklist(title: "Apple TV") {
                Text("1. Apple Configurator에서 Apple TV를 페어링하고 저장한 프로필을 TV로 드래그합니다.")
                Text("2. TV의 설정 > 일반 > 프로필 > 프로필 추가에 http://prog/ssl 을 입력해 CA 프로필을 설치합니다.")
                Text("3. 설정 > 일반 > 정보 > 인증서 신뢰 설정에서 EyeProxy CA를 신뢰로 켭니다.")
            }
            Text("Apple Watch: 짝지은 iPhone에 프로필을 설치하면 Watch로 전달됩니다").font(.callout)
        }
    }
}

private struct Checklist<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
        .font(.callout)
        .textSelection(.enabled)
    }
}
