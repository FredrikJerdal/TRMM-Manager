import SwiftUI
import StoreKit

struct DonationSheet: View {
    private static let productIdentifiers = [
        "Donate1usd",
        "Donate5usd",
        "Donate10usd",
        "Donate20usd",
        "Donate50usd",
        "Donate100usd"
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var products: [Product] = []
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var isPurchasing = false
    @State private var showCelebration = false
    @State private var celebrationProgress: CGFloat = 0
    @State private var showConfetti = false
    @State private var confettiProgress: CGFloat = 0
    @State private var confettiSeed = 0

    private let confettiThreshold = Decimal(10)
    private var confettiColors: [Color] {
        [
            .red,
            .orange,
            .yellow,
            .green,
            .mint,
            .blue,
            .pink,
            appTheme.accent
        ]
    }

    private let celebrationOffsets: [CGSize] = [
        CGSize(width: 0, height: -170),
        CGSize(width: 78, height: -152),
        CGSize(width: 136, height: -98),
        CGSize(width: 162, height: -26),
        CGSize(width: 142, height: 62),
        CGSize(width: 84, height: 138),
        CGSize(width: 0, height: 170),
        CGSize(width: -86, height: 138),
        CGSize(width: -142, height: 62),
        CGSize(width: -162, height: -26),
        CGSize(width: -136, height: -98),
        CGSize(width: -78, height: -152)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DarkGradientBackground()
                VStack(spacing: 20) {
                    Text("Support Development")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.white)
                    Text("Select a donation amount to support ongoing work on TacticalRMM Manager.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal)

                    if isLoading {
                        ProgressView("Loading donation options…")
                            .tint(appTheme.accent)
                    } else if products.isEmpty {
                        Text("Donation options are currently unavailable. Check back soon.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(products, id: \.id) { product in
                                Button {
                                    Task { await purchase(product) }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(product.displayPrice)
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(appTheme.accent)
                                .buttonBorderShape(.roundedRectangle(radius: 14))
                                .disabled(isPurchasing)
                            }
                        }
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(24)

                if showCelebration {
                    celebrationOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if showConfetti {
                    confettiOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .navigationTitle("Donate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(appTheme.accent)
                }
            }
        }
        .task {
            if products.isEmpty {
                await loadProducts()
            }
        }
    }

    @MainActor
    private func loadProducts() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }
        do {
            var fetched = try await Product.products(for: Self.productIdentifiers)
            fetched.sort { $0.price < $1.price }
            products = fetched
            let identifiers = fetched.map { $0.id.description }.joined(separator: ", ")
            DiagnosticLogger.shared.append("Loaded StoreKit products: \(identifiers)")
        } catch {
            statusMessage = "Unable to load donation options: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    statusMessage = "Thank you for your support!"
                    if product.price >= confettiThreshold {
                        triggerConfetti()
                    } else {
                        triggerCelebration()
                    }
                case .unverified(_, let error):
                    statusMessage = "Donation unverified: \(error.localizedDescription)"
                }
            case .userCancelled:
                statusMessage = "Donation cancelled."
            case .pending:
                statusMessage = "Donation pending approval."
            @unknown default:
                statusMessage = "Donation completed with an unknown result."
            }
        } catch {
            statusMessage = "Donation failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        ZStack {
            Circle()
                .fill(appTheme.accent.opacity(0.28))
                .frame(width: 180, height: 180)
                .blur(radius: 16)
                .scaleEffect(0.55 + (celebrationProgress * 1.65))
                .opacity(1 - celebrationProgress)

            ForEach(Array(celebrationOffsets.enumerated()), id: \.offset) { index, destination in
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "heart.fill")
                    .font(.system(size: index.isMultiple(of: 3) ? 20 : 15, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? Color.white : appTheme.accent)
                    .offset(
                        x: destination.width * celebrationProgress,
                        y: destination.height * celebrationProgress
                    )
                    .scaleEffect(0.65 + (celebrationProgress * 0.95))
                    .opacity(1 - celebrationProgress)
            }
        }
    }

    @ViewBuilder
    private var confettiOverlay: some View {
        GeometryReader { proxy in
            let count = 42
            let verticalTravel = proxy.size.height + 120

            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let lane = CGFloat((index * 37 + confettiSeed * 17) % 100) / 100
                    let startX = proxy.size.width * lane
                    let drift = CGFloat(sin(Double(index) * 1.47)) * 70
                    let wobble = CGFloat(cos(Double(index) * 1.11)) * 16
                    let startYOffset = CGFloat((index % 6) * -28)
                    let rotation = Double((index * 31 + confettiSeed * 13) % 360)
                    let width = CGFloat(6 + (index % 6))
                    let height = CGFloat(10 + ((index * 2) % 10))
                    let color = confettiColors[index % confettiColors.count]
                    let fade = max(0, min(1, (1 - confettiProgress) * 1.35))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: width, height: height)
                        .rotationEffect(.degrees(rotation + Double(confettiProgress * 420)))
                        .offset(
                            x: startX + (drift * confettiProgress),
                            y: startYOffset + (verticalTravel * confettiProgress) + (wobble * sin(confettiProgress * .pi * 2.2))
                        )
                        .opacity(fade)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
    }

    private func triggerCelebration() {
        celebrationProgress = 0
        withAnimation(.easeInOut(duration: 0.12)) {
            showCelebration = true
        }
        withAnimation(.easeOut(duration: 1.1)) {
            celebrationProgress = 1
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCelebration = false
                }
                celebrationProgress = 0
            }
        }
    }

    private func triggerConfetti() {
        confettiSeed += 1
        confettiProgress = 0

        withAnimation(.easeIn(duration: 0.08)) {
            showConfetti = true
        }

        withAnimation(.timingCurve(0.18, 0.76, 0.24, 1.0, duration: 2.6)) {
            confettiProgress = 1
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_900_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showConfetti = false
                }
                confettiProgress = 0
            }
        }
    }
}
