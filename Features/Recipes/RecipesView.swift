import SwiftUI

struct RecipesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddRecipe = false

    var body: some View {
        NavigationStack {
            List {
                if store.recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Ask me in Chat to create a recipe, or add one manually.")
                    )
                } else {
                    ForEach(store.recipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            RecipeRow(recipe: recipe)
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddRecipe = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                AddRecipeSheet().environment(store)
            }
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                HStack {
                    Label("\(recipe.servings) servings", systemImage: "person.2")
                    if !recipe.tags.isEmpty {
                        Text("·")
                        Text(recipe.tags.prefix(2).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe

    var body: some View {
        List {
            if !recipe.ingredients.isEmpty {
                Section("Ingredients") {
                    ForEach(recipe.ingredients) { ingredient in
                        HStack {
                            Text(ingredient.productName)
                            Spacer()
                            Text("\(ingredient.quantity.formatted()) \(ingredient.unit.rawValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !recipe.steps.isEmpty {
                Section("Method") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        Label(step, systemImage: "\(i + 1).circle")
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
