import Foundation
import Supabase

/// Day screen data. `get_day`, `set_day_target`, entry delete, entry photos.
public struct DayClient: Sendable {
  public var fetchDay: @Sendable (DateKey) async throws -> DayBundle
  public var setTarget:
    @Sendable (_ date: DateKey, _ targetId: UUID, _ today: DateKey) async throws -> Void
  public var deleteEntry: @Sendable (UUID) async throws -> Void
  public var imageURL: @Sendable (_ path: String) async throws -> URL

  public init(
    fetchDay: @escaping @Sendable (DateKey) async throws -> DayBundle,
    setTarget: @escaping @Sendable (DateKey, UUID, DateKey) async throws -> Void,
    deleteEntry: @escaping @Sendable (UUID) async throws -> Void,
    imageURL: @escaping @Sendable (String) async throws -> URL
  ) {
    self.fetchDay = fetchDay
    self.setTarget = setTarget
    self.deleteEntry = deleteEntry
    self.imageURL = imageURL
  }
}

/// Logging writes. `log_food_entry`, `save_meal`, photo upload.
public struct LoggingClient: Sendable {
  public var logEntry: @Sendable (LogPayload) async throws -> Void
  public var saveMeal:
    @Sendable (_ id: UUID?, _ name: String, _ ingredients: [SavedMealIngredient]) async throws ->
      UUID
  /// Uploads a JPEG to `<user_id>/<entry_id>.jpg` and returns the path.
  public var uploadImage: @Sendable (_ jpeg: Data, _ entryId: UUID) async throws -> String

  public init(
    logEntry: @escaping @Sendable (LogPayload) async throws -> Void,
    saveMeal: @escaping @Sendable (UUID?, String, [SavedMealIngredient]) async throws -> UUID,
    uploadImage: @escaping @Sendable (Data, UUID) async throws -> String
  ) {
    self.logEntry = logEntry
    self.saveMeal = saveMeal
    self.uploadImage = uploadImage
  }
}

/// Saved foods and meals.
public struct LibraryClient: Sendable {
  public var list: @Sendable () async throws -> [SavedFood]
  public var ingredients: @Sendable (_ mealId: UUID) async throws -> [SavedMealIngredient]
  public var insertFood: @Sendable (SavedFoodDraft) async throws -> SavedFood
  public var updateFood: @Sendable (UUID, SavedFoodDraft) async throws -> SavedFood
  public var deleteFood: @Sendable (UUID) async throws -> Void
  public var setFavorite: @Sendable (UUID, Bool) async throws -> Void
  /// Exact case-insensitive name match among non-meal foods.
  public var findDuplicate: @Sendable (String) async throws -> SavedFood?

  public init(
    list: @escaping @Sendable () async throws -> [SavedFood],
    ingredients: @escaping @Sendable (UUID) async throws -> [SavedMealIngredient],
    insertFood: @escaping @Sendable (SavedFoodDraft) async throws -> SavedFood,
    updateFood: @escaping @Sendable (UUID, SavedFoodDraft) async throws -> SavedFood,
    deleteFood: @escaping @Sendable (UUID) async throws -> Void,
    setFavorite: @escaping @Sendable (UUID, Bool) async throws -> Void,
    findDuplicate: @escaping @Sendable (String) async throws -> SavedFood?
  ) {
    self.list = list
    self.ingredients = ingredients
    self.insertFood = insertFood
    self.updateFood = updateFood
    self.deleteFood = deleteFood
    self.setFavorite = setFavorite
    self.findDuplicate = findDuplicate
  }
}

/// Daily target CRUD.
public struct TargetsClient: Sendable {
  public var list: @Sendable () async throws -> [DailyTarget]
  public var save:
    @Sendable (_ id: UUID?, _ name: String, _ macros: MacroTotals, _ today: DateKey) async throws ->
      UUID
  public var delete: @Sendable (_ id: UUID, _ today: DateKey) async throws -> Void

  public init(
    list: @escaping @Sendable () async throws -> [DailyTarget],
    save: @escaping @Sendable (UUID?, String, MacroTotals, DateKey) async throws -> UUID,
    delete: @escaping @Sendable (UUID, DateKey) async throws -> Void
  ) {
    self.list = list
    self.save = save
    self.delete = delete
  }
}

// MARK: - Live

extension DayClient {
  public static let live = DayClient(
    fetchDay: { date in
      let data = try await SupabaseProvider.client
        .rpc("get_day", params: ["p_date": date.rawValue]).execute().data
      return try JSONDecoder.ezha.decode(DayBundle.self, from: data)
    },
    setTarget: { date, targetId, today in
      try await SupabaseProvider.client.rpc(
        "set_day_target",
        params: RPCParams([
          "p_date": date.rawValue, "p_target_id": targetId, "p_today": today.rawValue,
        ])
      ).execute()
    },
    deleteEntry: { id in
      try await SupabaseProvider.client.from("food_entries").delete().eq("id", value: id)
        .execute()
    },
    imageURL: { path in
      try await SupabaseProvider.client.storage.from(SupabaseProvider.imagesBucket)
        .createSignedURL(path: path, expiresIn: 3600)
    }
  )
}

extension LoggingClient {
  public static let live = LoggingClient(
    logEntry: { payload in
      try await SupabaseProvider.client.rpc(
        "log_food_entry",
        params: RPCParams([
          "p_entry": payload.entry, "p_items": payload.items,
          "p_used_food_ids": payload.usedFoodIds, "p_time_slot": payload.timeSlot,
        ])
      ).execute()
    },
    saveMeal: { id, name, ingredients in
      let data = try await SupabaseProvider.client.rpc(
        "save_meal",
        params: RPCParams(["p_id": id, "p_name": name, "p_ingredients": ingredients])
      ).execute().data
      return try JSONDecoder.ezha.decode(UUID.self, from: data)
    },
    uploadImage: { jpeg, entryId in
      let userId = try await SupabaseProvider.client.auth.session.user.id
      let path = "\(userId.uuidString.lowercased())/\(entryId.uuidString.lowercased()).jpg"
      _ = try await SupabaseProvider.client.storage.from(SupabaseProvider.imagesBucket)
        .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
      return path
    }
  )
}

extension LibraryClient {
  public static let live = LibraryClient(
    list: {
      let data = try await SupabaseProvider.client.from("saved_foods").select()
        .order("name").execute().data
      return try JSONDecoder.ezha.decode([SavedFood].self, from: data)
    },
    ingredients: { mealId in
      let data = try await SupabaseProvider.client.from("saved_meal_ingredients").select()
        .eq("meal_id", value: mealId).order("created_at").execute().data
      return try JSONDecoder.ezha.decode([SavedMealIngredient].self, from: data)
    },
    insertFood: { draft in
      let userId = try await SupabaseProvider.client.auth.session.user.id
      let data = try await SupabaseProvider.client.from("saved_foods")
        .insert(NewFoodRow(userId: userId, draft: draft)).select().single().execute().data
      return try JSONDecoder.ezha.decode(SavedFood.self, from: data)
    },
    updateFood: { id, draft in
      let data = try await SupabaseProvider.client.from("saved_foods").update(draft)
        .eq("id", value: id).select().single().execute().data
      return try JSONDecoder.ezha.decode(SavedFood.self, from: data)
    },
    deleteFood: { id in
      try await SupabaseProvider.client.from("saved_foods").delete().eq("id", value: id).execute()
    },
    setFavorite: { id, isFavorite in
      try await SupabaseProvider.client.from("saved_foods").update(["is_favorite": isFavorite])
        .eq("id", value: id).execute()
    },
    findDuplicate: { name in
      // ilike without wildcards is a case-insensitive equality; escape the pattern characters.
      let pattern = name.trimmed.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
      guard !pattern.isEmpty else { return nil }
      let data = try await SupabaseProvider.client.from("saved_foods").select()
        .eq("is_meal", value: false).ilike("name", pattern: pattern).limit(20).execute().data
      let foods = try JSONDecoder.ezha.decode([SavedFood].self, from: data)
      return LibraryDrafts.duplicate(of: name, in: foods)
    }
  )
}

extension TargetsClient {
  public static let live = TargetsClient(
    list: {
      let data = try await SupabaseProvider.client.from("daily_targets").select()
        .order("created_at").execute().data
      return try JSONDecoder.ezha.decode([DailyTarget].self, from: data)
    },
    save: { id, name, macros, today in
      let data = try await SupabaseProvider.client.rpc(
        "save_daily_target",
        params: RPCParams([
          "p_id": id, "p_name": name, "p_calories": macros.calories,
          "p_protein": macros.protein, "p_carbs": macros.carbs, "p_fat": macros.fat,
          "p_today": today.rawValue,
        ])
      ).execute().data
      return try JSONDecoder.ezha.decode(UUID.self, from: data)
    },
    delete: { id, today in
      try await SupabaseProvider.client.rpc(
        "delete_daily_target", params: RPCParams(["p_id": id, "p_today": today.rawValue])
      ).execute()
    }
  )
}

extension SupabaseProvider {
  public static let imagesBucket = "food-images"
}

/// RPC parameters by name. Optional values encode as JSON null.
struct RPCParams: Encodable {
  let values: [String: any Encodable]

  init(_ values: [String: any Encodable]) { self.values = values }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AnyKey.self)
    for (key, value) in values {
      try container.encode(value, forKey: AnyKey(stringValue: key))
    }
  }
}

struct AnyKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

/// A new `saved_foods` row: the draft plus owner and `is_meal = false`.
struct NewFoodRow: Encodable {
  let userId: UUID
  let draft: SavedFoodDraft

  func encode(to encoder: any Encoder) throws {
    try draft.encode(to: encoder)
    var container = encoder.container(keyedBy: AnyKey.self)
    try container.encode(userId, forKey: AnyKey(stringValue: "user_id"))
    try container.encode(false, forKey: AnyKey(stringValue: "is_meal"))
  }
}
