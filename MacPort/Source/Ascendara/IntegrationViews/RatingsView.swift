import SwiftUI

struct RatingsView: View {
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    let Game: Game
    @State private var Rating: GameRating?
    @State private var IsLoading = false
    @State private var ErrorMessage: String?
    @State private var RefreshTask: Task<Void, Never>?
    @State private var RequestId = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: IsTV ? 28 * Scale : 18) {
            HStack(spacing: IsTV ? 24 * Scale : 8) {
                if IsTV {
                    VStack(alignment: .leading, spacing: 10 * Scale) {
                        Text(I18n.T("Community reviews")).font(.system(size: 30 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text)
                        Text(I18n.T("Ratings from Ascendara players")).font(.system(size: 19 * Scale)).foregroundStyle(TVStyle.Secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: Refresh) { Label(I18n.T("Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(TVButtonStyle()).disabled(IsLoading).accessibilityLabel(I18n.T("Refresh reviews"))
                } else {
                    SectionHeading(Title: I18n.T("Community reviews"), Subtitle: I18n.T("Ratings from Ascendara players"), Symbol: "bubble.left.and.bubble.right")
                    if let Rating {
                        Text(I18n.Interpolated("\(Rating.Reviews.count)"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Theme.Accent.opacity(0.12), in: Capsule())
                    }
                    Button(action: Refresh) { Image(systemName: "arrow.clockwise") }.disabled(IsLoading).help(I18n.T("Refresh reviews"))
                }
            }
            if IsLoading {
                ProgressView("Loading reviews…").font(IsTV ? .system(size: 20 * Scale) : .body)
                    .controlSize(IsTV ? .large : .regular).frame(maxWidth: .infinity).padding(IsTV ? 46 * Scale : 30)
            } else if let ErrorMessage {
                Notice(Message: ErrorMessage, Symbol: "exclamationmark.triangle")
                Button(I18n.T("Try again"), action: Refresh).buttonStyle(SecondaryButtonStyle())
            } else if let Rating {
                if IsTV {
                    Panel(Padding: 28) {
                        HStack(spacing: 24 * Scale) {
                            Text(Rating.Average.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 54 * Scale, weight: .bold))
                            VStack(alignment: .leading, spacing: 10 * Scale) {
                                Stars(Rating.Average)
                                Text(I18n.Interpolated("\(Rating.Count) ratings")).font(.system(size: 19 * Scale)).foregroundStyle(Theme.SecondaryText)
                            }
                            Spacer()
                        }
                    }
                } else {
                    HStack(spacing: 9) {
                        Stars(Rating.Average)
                        Text(I18n.Interpolated("\(Rating.Average.formatted(.number.precision(.fractionLength(1)))) / 5 · \(Rating.Count) ratings"))
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                    }
                }
                if Rating.Reviews.isEmpty {
                    if IsTV {
                        TVEmptyState(Symbol: "text.bubble", Title: I18n.T("No written reviews yet"), Message: I18n.T("Written reviews appear here when players share their experience."))
                    } else {
                        EmptyPanel(Symbol: "text.bubble", Title: I18n.T("No written reviews yet"), Message: I18n.T("Written reviews appear here when players share their experience."))
                    }
                }
                if IsTV {
                    ForEach(Rating.Reviews) { Review in ReviewCard(Review) }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(Rating.Reviews) { Review in ReviewCard(Review) }
                    }
                }
            }
        }.MotionAnimation(IsLoading)
            .task(id: Game.Id) {
                RefreshTask?.cancel()
                Rating = nil
                await Load()
            }.onDisappear { RefreshTask?.cancel() }
    }

    private func ReviewCard(_ Review: GameReview) -> some View {
        Panel(Padding: IsTV ? 28 : 22) {
            VStack(alignment: .leading, spacing: IsTV ? 24 * Scale : 12) {
                HStack(spacing: IsTV ? 18 * Scale : 8) {
                    Image(systemName: Review.IsGuest ? "person.crop.circle" : "person.crop.circle.fill")
                        .font(.system(size: IsTV ? 42 * Scale : 26)).foregroundStyle(Theme.Accent)
                    VStack(alignment: .leading, spacing: IsTV ? 8 * Scale : 4) {
                        Text(Review.Username).font(.system(size: IsTV ? 23 * Scale : 13, weight: .semibold))
                        if let CreatedAt = Review.CreatedAt {
                            Text(String(CreatedAt.prefix(10))).font(IsTV ? .system(size: 17 * Scale) : .caption2).foregroundStyle(Theme.SecondaryText)
                        }
                    }
                    Spacer()
                    Stars(Review.Rating)
                }
                Text(Review.Comments).font(.system(size: IsTV ? 21 * Scale : 13))
                    .lineSpacing(IsTV ? 7 * Scale : 4).textSelection(.enabled)
                if !IsTV { Spacer(minLength: 4) }
            }.frame(maxWidth: .infinity, minHeight: IsTV ? 0 : 180, alignment: .topLeading)
        }
    }

    private func Stars(_ Rating: Double) -> some View {
        HStack(spacing: IsTV ? 6 * Scale : 3) {
            ForEach(1...5, id: \.self) { Index in
                Image(systemName: Double(Index) <= Rating ? "star.fill" : (Double(Index) - 0.5 <= Rating ? "star.leadinghalf.filled" : "star"))
                    .foregroundStyle(.orange)
            }
        }.font(.system(size: IsTV ? 21 * Scale : 12)).accessibilityLabel(I18n.Interpolated("\(Rating.formatted(.number.precision(.fractionLength(1)))) out of 5 stars"))
    }

    private func Refresh() {
        RefreshTask?.cancel()
        RefreshTask = Task { await Load(Force: true) }
    }

    private func Load(Force: Bool = false) async {
        let Request = UUID()
        RequestId = Request
        IsLoading = true
        ErrorMessage = nil
        defer { if RequestId == Request { IsLoading = false } }
        do {
            let Result = try await RatingService.Shared.Load(GameId: Game.Id, Force: Force)
            try Task.checkCancellation()
            if RequestId == Request { Rating = Result }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled && RequestId == Request { ErrorMessage = error.localizedDescription }
        }
    }
}
