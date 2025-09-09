import SwiftUI
import Vision
import AppKit
import UniformTypeIdentifiers

// 選択された画像を表すデータ構造
struct SelectedImage: Identifiable {
    let id = UUID()
    let url: URL
    var image: NSImage?
}

struct ContentView: View {
    @State private var selectedImages: [SelectedImage] = []
    @State private var recognizedText: String = "ここにOCR結果が表示されます。"
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    
    @State private var showingPreview = false
    @State private var currentImage: NSImage?
    
    @State private var exclusionList: [String] = []
    @State private var showingFileImporter = false
    @State private var dictionaryStatus: String = "辞書ファイルが選択されていません"

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                
                // プレビュー表示エリア
                ScrollView(.horizontal) {
                    HStack(spacing: 15) {
                        ForEach(selectedImages) { selectedImage in
                            ZStack(alignment: .topTrailing) {
                                if let image = selectedImage.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(12)
                                        .shadow(radius: 5)
                                        .onTapGesture {
                                            self.currentImage = selectedImage.image
                                            self.showingPreview = true
                                        }
                                }
                                Button(action: {
                                    removeImage(id: selectedImage.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 180)

                // 辞書選択エリア
                VStack(spacing: 10) {
                    Text(dictionaryStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        showingFileImporter = true
                    }) {
                        Label("辞書ファイルを選択", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)

                if isProcessing {
                    ProgressView(value: progress, total: 100)
                        .padding(.horizontal, 20)
                }
                
                // OCR結果を表示するテキストエリア
                TextEditor(text: $recognizedText)
                    .font(.body)
                    .border(Color.gray.opacity(0.5), width: 1)
                    .frame(minHeight: 200, maxHeight: .infinity)
                
                HStack {
                    Button(action: selectImages) {
                        Label("画像を選択", systemImage: "photo.on.rectangle.angled")
                    }

                    Button(action: performOcr) {
                        Label("OCRを実行", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(selectedImages.isEmpty || isProcessing)

                    Spacer()
                    
                    Button(action: copyToClipboard) {
                        Label("結果をコピー", systemImage: "doc.on.doc")
                    }
                    .disabled(recognizedText.isEmpty || recognizedText == "ここにOCR結果が表示されます。")
                }
                .padding(.horizontal, 20)
            }
            .padding()
            .frame(minWidth: 600, minHeight: 500)
            
            if showingPreview, let image = currentImage {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .onTapGesture {
                            self.showingPreview = false
                        }
                    
                    VStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20)
                        
                        Button("閉じる") {
                            self.showingPreview = false
                        }
                        .padding()
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(width: 800, height: 600)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeIn, value: showingPreview)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadDictionary(from: url)
                }
            case .failure(let error):
                dictionaryStatus = "辞書ファイルの選択に失敗: \(error.localizedDescription)"
            }
        }
    }
    
    // 辞書ファイルを読み込む関数
    private func loadDictionary(from url: URL) {
        do {
            // ファイルアクセス権限を取得
            let _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            let fileContent = try String(contentsOf: url, encoding: .utf8)
            exclusionList = fileContent.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            dictionaryStatus = "辞書ファイル読み込み完了 (\(exclusionList.count)単語)"
            print("辞書ファイルを読み込みました。除外単語: \(exclusionList)")
        } catch {
            dictionaryStatus = "辞書ファイルの読み込みに失敗: \(error.localizedDescription)"
            print("辞書ファイル読み込みエラー: \(error)")
        }
    }
    
    private func selectImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            selectedImages = panel.urls.map { url in
                SelectedImage(url: url, image: NSImage(contentsOf: url))
            }
        }
    }
    
    private func removeImage(id: UUID) {
        selectedImages.removeAll { $0.id == id }
    }
    
    private func performOcr() {
        isProcessing = true
        recognizedText = ""
        progress = 0.0
        
        guard !selectedImages.isEmpty else {
            recognizedText = "画像を先に選択してください。"
            isProcessing = false
            return
        }

        let totalImages = selectedImages.count
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allRecognizedText = ""
            for (index, imageItem) in selectedImages.enumerated() {
                guard let image = imageItem.image,
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    allRecognizedText += "エラー: 画像を読み込めませんでした。\n\n"
                    continue
                }
                
                let request = VNRecognizeTextRequest { (request, error) in
                    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                        allRecognizedText += "エラー: OCRに失敗しました。\n\n"
                        return
                    }
                    
                    var formattedResult = ""
                    for observation in observations {
                        if let recognizedText = observation.topCandidates(1).first?.string {
                            let trimmedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            // 辞書に登録されている単語は[]で囲まない
                            if self.exclusionList.contains(trimmedText) {
                                formattedResult += "\(trimmedText)\n"
                            } else {
                                formattedResult += "[\(trimmedText)]\n"
                            }
                        }
                    }
                    allRecognizedText += formattedResult + "\n"
                }
                
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ja"]
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    allRecognizedText += "エラー: Visionリクエストの実行に失敗しました。\n\n"
                }
                
                DispatchQueue.main.async {
                    self.progress = Double(index + 1) / Double(totalImages) * 100
                }
            }
            
            DispatchQueue.main.async {
                self.recognizedText = allRecognizedText
                self.isProcessing = false
            }
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recognizedText, forType: .string)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // updateメソッドは実装が必要だが、今回は何も処理しない
    }
}
