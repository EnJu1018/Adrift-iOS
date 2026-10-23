import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var refreshManager: AppRefreshManager
    @State private var copied = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingAvatarData: Data?
    @State private var pendingAvatarMimeType = "image/jpeg"
    @State private var editingField: ProfileField?

    var body: some View {
        Group {
            ZStack {
                AdriftBackground()

                List {
                    if let user = authViewModel.currentUser {
                        Section {
                            GlassCard {
                                HStack(spacing: 18) {
                                    avatarPreview(for: user)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(user.name)
                                            .font(AdriftTypography.title)
                                        if let email = user.email {
                                            Text(email)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Label("@\(user.userCode)", systemImage: "at")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                        }

                        Section("個人資料") {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("選擇頭貼", systemImage: "photo")
                            }

                            if pendingAvatarData != nil {
                                Button {
                                    Task { await saveAvatar() }
                                } label: {
                                    if authViewModel.isUploadingAvatar {
                                        ProgressView()
                                    } else {
                                        Label("儲存頭貼", systemImage: "square.and.arrow.up")
                                    }
                                }
                                .tint(AdriftColors.ocean)
                                .disabled(authViewModel.isUploadingAvatar)

                            }

                            Button { editingField = .name } label: {
                                LabeledContent("名稱", value: user.name)
                            }
                            Button { editingField = .email } label: {
                                LabeledContent("電子郵件", value: user.email ?? "")
                            }
                            if user.avatarUrl?.isEmpty == false {
                                Button(role: .destructive) {
                                    Task { await authViewModel.removeAvatar() }
                                } label: { Label("移除頭像", systemImage: "person.crop.circle.badge.minus") }
                                    .disabled(authViewModel.isLoading)
                            }
                        }

                        Section("Adrift ID") {
                            LabeledContent("使用者 ID") {
                                HStack {
                                    Text(user.userCode)
                                        .font(.body.monospaced())
                                    Button {
                                        UIPasteboard.general.string = user.userCode
                                        copied = true
                                    } label: {
                                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                            .foregroundStyle(copied ? AdriftColors.calm : AdriftColors.ocean)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            LabeledContent("角色", value: user.role == "owner" ? "擁有者" : user.role == "admin" ? "管理員" : "使用者")
                        }

                        Section("帳號安全") {
                            Button {
                                editingField = .password
                            } label: {
                                Label("修改密碼", systemImage: "lock.rotation")
                            }
                        }
                    }

                    Section("危險區域") {
                        Button(role: .destructive) {
                            authViewModel.logout()
                        } label: {
                            Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                .adriftListLayout()
            }
            .adriftPageNavigation("帳號設定")
            .task {
                await refreshManager.refreshIfNeeded(scopes: [.user])
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .sheet(item: $editingField) { ProfileEditView(field: $0) }
            .alert("發生問題", isPresented: .constant(authViewModel.errorMessage != nil)) {
                Button("好") { authViewModel.errorMessage = nil }
            } message: {
                Text(authViewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func avatarPreview(for user: User) -> some View {
        if let pendingAvatarData, let image = UIImage(data: pendingAvatarData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(AdriftColors.cyan, lineWidth: 2)
                }
                .accessibilityLabel("新頭貼預覽")
        } else {
            AvatarView(name: user.name, avatarUrl: user.avatarUrl, size: 72)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.resizedForDiaryUpload().jpegData(compressionQuality: 0.82) else {
                throw APIError.server(message: "無法讀取這張照片", statusCode: 0)
            }
            guard selectedPhoto == item else { return }
            pendingAvatarMimeType = "image/jpeg"
            pendingAvatarData = jpeg
        } catch { authViewModel.errorMessage = "照片載入失敗，請重新選擇" }
    }

    private func saveAvatar() async {
        guard let pendingAvatarData else { return }
        await authViewModel.uploadAvatar(data: pendingAvatarData, mimeType: pendingAvatarMimeType)
        if authViewModel.errorMessage == nil {
            selectedPhoto = nil
            self.pendingAvatarData = nil
        }
    }
}

private enum ProfileField: String, Identifiable {
    case name, email, password
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "修改名稱"
        case .email: "修改電子郵件"
        case .password: "修改密碼"
        }
    }
}

private struct ProfileEditView: View {
    let field: ProfileField
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                if field == .password {
                    SecureField("目前密碼", text: $password).textContentType(.password)
                    SecureField("新密碼", text: $value).textContentType(.newPassword)
                    SecureField("確認新密碼", text: $confirmPassword).textContentType(.newPassword)
                } else {
                    TextField(field == .name ? "名稱" : "電子郵件", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(field == .email ? .emailAddress : .default)
                    if field == .email { SecureField("目前密碼", text: $password) }
                }
                if let error = auth.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(auth.isLoading) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if auth.isLoading { ProgressView() } else { Label("儲存", systemImage: "checkmark") }
                    }
                    .disabled(auth.isLoading || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(auth.isLoading)
            .onAppear {
                auth.errorMessage = nil
                value = field == .name ? auth.currentUser?.name ?? "" : field == .email ? auth.currentUser?.email ?? "" : ""
            }
        }
    }

    private func save() async {
        let values: [String: String]
        switch field {
        case .name: values = ["name": value]
        case .email: values = ["email": value, "password": password]
        case .password: values = ["currentPassword": password, "newPassword": value, "confirmPassword": confirmPassword]
        }
        if await auth.updateProfile(field: field.rawValue, values: values) { dismiss() }
    }
}
