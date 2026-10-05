-- Add is_meal column to saved_foods
ALTER TABLE public.saved_foods ADD COLUMN IF NOT EXISTS is_meal boolean NOT NULL DEFAULT false;

-- Create saved_meal_ingredients table
CREATE TABLE IF NOT EXISTS public.saved_meal_ingredients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meal_id uuid NOT NULL REFERENCES public.saved_foods(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name text NOT NULL,
    grams numeric NOT NULL CHECK (grams > 0),
    calories numeric NOT NULL DEFAULT 0,
    protein numeric NOT NULL DEFAULT 0,
    carbs numeric NOT NULL DEFAULT 0,
    fat numeric NOT NULL DEFAULT 0,
    linked_food_id uuid REFERENCES public.saved_foods(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS saved_meal_ingredients_meal_idx ON public.saved_meal_ingredients (meal_id);
CREATE INDEX IF NOT EXISTS saved_meal_ingredients_user_idx ON public.saved_meal_ingredients (user_id);

-- Enable RLS
ALTER TABLE public.saved_meal_ingredients ENABLE ROW LEVEL SECURITY;

-- RLS policy
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'saved_meal_ingredients' AND policyname = 'Saved meal ingredients all'
    ) THEN
        CREATE POLICY "Saved meal ingredients all" ON public.saved_meal_ingredients
            FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;
END
$$;;
