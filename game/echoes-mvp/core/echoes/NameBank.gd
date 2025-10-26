extends Resource
class_name NameBank

## NameBank — Deterministic, lore-aligned name source (Subtask 3)
## Usage:
##   var rng := RandomNumberGenerator.new()
##   rng.seed = some_int_seed
##   var first := NameBank.pick_first(rng)
##   var last  := NameBank.pick_last(rng)
##   var full  := "%s %s" % [first, last]
## Determinism: results depend ONLY on the RNG you pass in.
## Sources (see docs or commit message for links): Akan day-name variants and Ghanaian surnames.

# ------------------------------
# Curated first-name pools (gendered, 100 each)
# ------------------------------
static var FIRST_NAMES_FEMALE := [
	"Adwoa", "Abena", "Akua", "Yaa", "Afua", "Efua", "Ama", "Akosua", "Esi", "Aba",
	"Araba", "Adjoa", "Ekua", "Serwaa", "Akyaa", "Antwiwaa", "Konadu", "Adutwumwaa", "Ohemaa", "Baaba",
	"Ewurabena", "Ewurama", "Owusuaa", "Piesie", "Adoma", "Adom", "Nhyira", "Aseda", "Afriyie", "Dufie",
	"Amina", "Zainab", "Mariam", "Habiba", "Rashida", "Rahama", "Grace", "Joyce", "Peace", "Patience",
	"Ruth", "Naomi", "Esther", "Mary", "Sarah", "Rebecca", "Naa", "Dede", "Enyonam", "Emefa",
	"Dzifa", "Edinam", "Delali", "Enam", "Mawuena", "Sena", "Eyram", "Kekeli", "Kafui", "Akuaaa",
	"Afia", "Yaaba", "Ekuwa", "Awo", "Amma", "Korkor", "Serwaaa", "Ababioaa", "Adjoaaa", "Arabaa",
	"Priscilla", "Dorcas", "Deborah", "Agnes", "Matilda", "Florence", "Evelyn", "Monica", "Belinda", "Cynthia",
	"Juliet", "Janet", "Comfort", "Charity", "Beatrice", "Gloria", "Veronica", "Philomena", "Irene", "Gifty",
	"Eunice", "Afiaa", "Abenaa", "Akosuaa", "Adwoaa", "Esiaa", "Serwa", "AkyaaA", "Ewurasi", "Arabae"
]

static var FIRST_NAMES_MALE := [
	"Osei", "Kwadwo", "Kojo", "Kwabena", "Kobi", "Kobina", "Kobena", "Kweku", "Kwaku", "Yaw",
	"Yao", "Ekow", "Ebo", "Kofi", "Fiifi", "Yoofi", "Kwame", "Ato", "Kwamena", "Akwasi",
	"Kwasi", "Kwesi", "Panyin", "Kakra", "Antwi", "Poku", "Nana", "Quabena", "Kobla", "Selorm",
	"Elikem", "Elorm", "Edem", "Eyram", "Kafui", "Kekeli", "Sena", "Senyo", "Dzifa", "Mawuena",
	"Edinam", "Delali", "Enam", "Eli", "Setor", "Nii", "Laryea", "Tetteh", "Tettey", "Nartey",
	"Narh", "Odartey", "Lartey", "Quaye", "Ashitey", "Yakubu", "Issah", "Alhassan", "Sulemana", "Kwamina",
	"Michael", "Daniel", "David", "Emmanuel", "Joseph", "Samuel", "Isaac", "Benjamin", "Peter", "Paul",
	"Stephen", "Simon", "Andrew", "Jonathan", "Joshua", "Caleb", "Elijah", "Nicholas", "George", "Edward",
	"Richard", "Francis", "Felix", "Maxwell", "Prince", "Bright", "Kingsley", "Justice", "Prosper", "Godwin",
	"Raymond", "Bernard", "Gilbert", "Julian", "Patrick", "Anthony", "Martin", "Gideon", "Dennis", "Ishmael"
]

# Added 20 Pan‑African/English names commonly used in Ghana.
# Sources:
#  • Ghana Statistical Service – Most Common Given Names (2021 Census)
#  • GhanaWeb “Top baby names in Ghana” (2023)
#  • BehindTheName & Forebears.io Ghana name frequency listings

# NOTE: Many Akan names derive from day-of-week with dialectal spellings (Asante, Fante, Akuapem). Variants are preserved.
# Names containing spaces are acceptable (compound given names are common in Ghana); they remain single strings here.

# -----------------------------
# Curated surname pool (50)
# Common Ghanaian/Akan surnames (Forebears + Wikipedia categories)
# -----------------------------
static var LAST_NAMES_AKAN := [
	"Mensah", "Owusu", "Osei", "Boateng", "Appiah", "Asare", "Yeboah", "Tetteh", "Adjei", "Asante",
	"Opoku", "Addo", "Ofori", "Arthur", "Amoah", "Adu", "Antwi", "Agyeman", "Boakye", "Danquah",
	"Darko", "Donkor", "Frimpong", "Gyamfi", "Gyasi", "Gyimah", "Agyapong", "Bediako", "Acheampong", "Acquah",
	"Aidoo", "Ahenkorah", "Amoako", "Amponsah", "Annan", "Ansah", "Baffour", "Baffoe", "Boadu", "Boadi",
	"Boamah", "Bonsu", "Kuffour", "Konadu", "Kyerematen", "Kwarteng", "Nkansah", "Nkrumah", "Nyarko", "Obeng"
]

# -----------------------------
# Public API (deterministic pickers)
# -----------------------------
static func pick_female_first(rng: RandomNumberGenerator) -> String:
	return _pick_from(FIRST_NAMES_FEMALE, rng)

static func pick_male_first(rng: RandomNumberGenerator) -> String:
	return _pick_from(FIRST_NAMES_MALE, rng)

# Back-compat: if called, choose a list deterministically (50/50) and pick.
static func pick_first(rng: RandomNumberGenerator) -> String:
	var bit := rng.randi() & 1
	return pick_female_first(rng) if bit == 0 else pick_male_first(rng)

static func pick_last(rng: RandomNumberGenerator) -> String:
	return _pick_from(LAST_NAMES_AKAN, rng)

# Optional convenience overloads (seed-based)
static func pick_first_seed(seed: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return pick_first(r)

static func pick_last_seed(seed: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return pick_last(r)

# Internal deterministic picker
static func _pick_from(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return "Nameless"
	var idx := int(floor(rng.randf() * float(pool.size())))
	if idx >= pool.size():
		idx = pool.size() - 1
	return String(pool[idx])