import SwiftUI

struct RatingsView: View {
    let Game: Game
    @State private var Rating: GameRating?
    @State private var IsLoading = false
    @State private var ErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(Title: "Community reviews", Subtitle: "Ratings from Ascendara players", Symbol: "bubble.left.and.bubble.right")
                Button { Task { await Load(Force: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(IsLoading).help("Refresh reviews")
            }
            if IsLoading { ProgressView("Loading reviews…").frame(maxWidth: .infinity).padding(30) }
            else if let ErrorMessage {
                Notice(Message: ErrorMessage, Symbol: "exclamationmark.triangle")
                Button("Try again") { Task { await Load(Force: true) } }.buttonStyle(SecondaryButtonStyle())
            } else if let Rating {
                Panel {
                    HStack(spacing: 14) {
                        Text(Rating.Average.formatted(.number.precision(.fractionLength(1)))).font(.system(size: 34, weight: .bold))
                        VStack(alignment: .leading, spacing: 5) {
                            Stars(Rating.Average)
                            Text("\(Rating.Count) ratings").font(.caption).foregroundStyle(Theme.SecondaryText)
                        }
                        Spacer()
                    }
                }
                if Rating.Reviews.isEmpty {
                    EmptyPanel(Symbol: "text.bubble", Title: "No written reviews yet", Message: "Written reviews appear here when players share their experience.")
                }
                ForEach(Rating.Reviews) { Review in
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: Review.IsGuest ? "person.crop.circle" : "person.crop.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.Accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Review.Username).font(.system(size: 13, weight: .semibold))
                                    if let CreatedAt = Review.CreatedAt { Text(String(CreatedAt.prefix(10))).font(.caption2).foregroundStyle(Theme.SecondaryText) }
                                }
                                Spacer()
                                Stars(Review.Rating)
                            }
                            Text(Review.Comments).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }
            }
        }.MotionAnimation(IsLoading).task(id: Game.Id) { await Load() }
    }

    private func Stars(_ Rating: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { Index in
                Image(systemName: Double(Index) <= Rating ? "star.fill" : (Double(Index) - 0.5 <= Rating ? "star.leadinghalf.filled" : "star"))
                    .foregroundStyle(.orange)
            }
        }.font(.system(size: 12)).accessibilityLabel("\(Rating.formatted(.number.precision(.fractionLength(1)))) out of 5 stars")
    }

    private func Load(Force: Bool = false) async {
        IsLoading = true; ErrorMessage = nil
        defer { IsLoading = false }
        do { Rating = try await RatingService.Shared.Load(GameId: Game.Id, Force: Force) }
        catch is CancellationError {}
        catch { if !Task.isCancelled { ErrorMessage = error.localizedDescription } }
    }
}
