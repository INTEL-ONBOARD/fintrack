import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var auth: AuthSession
    @State private var conversations: [RemoteConversation] = []
    @State private var users: [RemoteChatUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = FinMateAPIClient()

    var body: some View {
        List {
            Section {
                BrandPageIntro(title: "Chat", subtitle: "Your conversations in one place.", icon: "message")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Conversations") {
                NavigationLink { ChatConversationView(conversationID: "group", title: "FinMate group") } label: {
                    Label("FinMate group", systemImage: "person.3")
                }
                ForEach(conversations) { conversation in
                    NavigationLink {
                        ChatConversationView(conversationID: conversation.id, title: conversation.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.id).font(.headline)
                            if let lastMessage = conversation.lastMessage {
                                Text(lastMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            Section("Start a conversation") {
                if users.isEmpty && !isLoading {
                    Text("No other users are available.").foregroundStyle(.secondary)
                }
                ForEach(users, id: \.stableID) { user in
                    if let conversationID = directConversationID(for: user) {
                        NavigationLink {
                            ChatConversationView(conversationID: conversationID, title: user.name ?? user.email ?? "Conversation")
                        } label: {
                            Label(user.name ?? user.email ?? "User", systemImage: "person")
                        }
                    }
                }
            }
        }
        .finTrackGroupedScreen()
        .navigationTitle("Chat")
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading { ProgressView() } }
        .alert("Unable to load chat", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        guard let token = auth.token() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await api.listConversations(accessToken: token)
            users = try await api.listChatUsers(accessToken: token)
        } catch { errorMessage = error.localizedDescription }
    }

    private func directConversationID(for user: RemoteChatUser) -> String? {
        guard let currentID = auth.user?.id, let userID = user.id else { return nil }
        return "dm_\([currentID, userID].sorted().joined(separator: "_"))"
    }
}

struct ChatConversationView: View {
    @EnvironmentObject private var auth: AuthSession
    let conversationID: String
    let title: String
    @State private var messages: [RemoteMessage] = []
    @State private var text = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    private let api = FinMateAPIClient()

    var body: some View {
        VStack(spacing: 0) {
            List(messages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.senderName).font(.caption.bold()).foregroundStyle(FinTrackStyle.black)
                    Text(message.body)
                    Text(message.sentAt).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .overlay { if isLoading { ProgressView() } }
            HStack(spacing: 8) {
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(12)
            .background(.white)
        }
        .finTrackGroupedScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Chat", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        guard let token = auth.token() else { return }
        isLoading = true
        defer { isLoading = false }
        do { messages = try await api.listMessages(conversationID: conversationID, accessToken: token) }
        catch { errorMessage = error.localizedDescription }
    }

    private func send() async {
        guard let token = auth.token() else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await api.sendMessage(conversationID: conversationID, body: body, accessToken: token)
            text = ""
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}
