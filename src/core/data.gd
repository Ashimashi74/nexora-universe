extends Node
## NEXORA static data — port of src/game/data.ts + util.ts + meta.ts + asset maps (assets.ts, menuAssets.ts).
## Autoload name: Data.  All field geometry values are floats (FS scaling already applied, like FIELDS in data.ts).

const FS := 1.12
const DEFAULT_FIELD := 0
const FIELDS_VERSION := 2
const CHEST_EVERY := 4 * 3600 * 1000  # ms

const GS := {"white": [840.0, 307.0, 0.0491, 0.9522], "wood": [840.0, 306.0, 0.0474, 0.9519], "ice": [840.0, 305.0, 0.0535, 0.9429], "black": [840.0, 235.0, 0.0521, 0.9527], "rope": [840.0, 246.0, 0.0493, 0.9528], "gold": [840.0, 237.0, 0.0431, 0.9521], "red": [840.0, 233.0, 0.0502, 0.9509], "blue": [840.0, 236.0, 0.0452, 0.9526]}
const FIELDS := [
	{"id": "pitch", "name": "NEXORA Pitch", "W": 837.0, "H": 1935.3, "L": 30.0, "R": 805.0, "T": 101.0, "B": 1831.3, "cs": 768.0, "g": 128.0, "gs": "white"},
	{"id": "forest", "name": "Forest", "W": 1216.0, "H": 2019.8, "L": 218.0, "R": 997.0, "T": 142.0, "B": 1865.8, "cs": 786.0, "g": 135.0, "gs": "wood"},
	{"id": "ice", "name": "Ice", "W": 1216.0, "H": 2016.5, "L": 213.0, "R": 1002.0, "T": 150.0, "B": 1859.5, "cs": 784.0, "g": 137.0, "gs": "ice"},
	{"id": "ocean", "name": "Ocean", "W": 1216.0, "H": 2027.0, "L": 214.0, "R": 1005.0, "T": 121.0, "B": 1876.0, "cs": 785.0, "g": 137.0, "gs": "blue"},
	{"id": "street", "name": "Street", "W": 1216.0, "H": 2010.5, "L": 204.0, "R": 1010.0, "T": 176.0, "B": 1859.5, "cs": 791.0, "g": 139.0, "gs": "gold"},
	{"id": "streetarena", "name": "Street Arena", "W": 1216.0, "H": 2022.5, "L": 217.0, "R": 995.0, "T": 131.0, "B": 1866.5, "cs": 786.0, "g": 135.0, "gs": "rope"},
	{"id": "lava", "name": "Lava", "W": 1216.0, "H": 2018.0, "L": 224.0, "R": 990.0, "T": 142.0, "B": 1858.0, "cs": 783.0, "g": 133.0, "gs": "black"},
	{"id": "stadium", "name": "Stadium", "W": 1216.0, "H": 2023.7, "L": 220.0, "R": 995.0, "T": 129.0, "B": 1869.7, "cs": 785.0, "g": 134.0, "gs": "white"},
	{"id": "checker", "name": "Checker", "W": 1216.0, "H": 2042.3, "L": 216.0, "R": 997.0, "T": 114.0, "B": 1935.3, "cs": 788.0, "g": 135.0, "gs": "red"},
	{"id": "futsal", "name": "Futsal", "W": 1216.0, "H": 2030.0, "L": 213.0, "R": 1002.0, "T": 116.0, "B": 1884.0, "cs": 781.0, "g": 137.0, "gs": "gold"},
	{"id": "arena", "name": "Arena", "W": 1216.0, "H": 2023.7, "L": 223.0, "R": 990.0, "T": 132.0, "B": 1872.7, "cs": 777.0, "g": 133.0, "gs": "red"},
	{"id": "arena2", "name": "Grand Arena", "W": 1216.0, "H": 2014.1, "L": 184.0, "R": 1032.0, "T": 151.0, "B": 1850.1, "cs": 787.0, "g": 139.0, "gs": "gold"},
	{"id": "desert", "name": "Desert", "W": 1216.0, "H": 2035.7, "L": 183.0, "R": 1030.0, "T": 94.0, "B": 1886.7, "cs": 777.0, "g": 139.0, "gs": "black"},
	{"id": "grove", "name": "Grove", "W": 1216.0, "H": 2029.1, "L": 193.0, "R": 1028.0, "T": 121.0, "B": 1885.1, "cs": 778.0, "g": 139.0, "gs": "rope"},
	{"id": "pool", "name": "Pool", "W": 1216.0, "H": 2029.7, "L": 179.0, "R": 1036.0, "T": 110.0, "B": 1876.7, "cs": 781.0, "g": 139.0, "gs": "white"},
	{"id": "neon", "name": "Neon Tech", "W": 1147.0, "H": 2141.2, "L": 158.0, "R": 989.0, "T": 147.0, "B": 1972.2, "cs": 834.0, "g": 145.0, "gs": "black"},
	{"id": "royal", "name": "Royal", "W": 1147.0, "H": 2124.1, "L": 166.0, "R": 982.0, "T": 165.0, "B": 1916.1, "cs": 818.0, "g": 141.0, "gs": "gold"},
	{"id": "mahogany", "name": "Mahogany", "W": 1147.0, "H": 2157.7, "L": 109.0, "R": 1036.0, "T": 101.0, "B": 1997.7, "cs": 816.0, "g": 161.0, "gs": "wood"},
	{"id": "leather", "name": "Leather", "W": 1147.0, "H": 2158.9, "L": 111.0, "R": 1036.0, "T": 111.0, "B": 2012.9, "cs": 818.0, "g": 160.0, "gs": "gold"},
	{"id": "aqua", "name": "Aquarium", "W": 1147.0, "H": 2146.0, "L": 137.0, "R": 1014.0, "T": 137.0, "B": 1983.0, "cs": 831.0, "g": 152.0, "gs": "blue"},
	{"id": "asphalt", "name": "Asphalt", "W": 1147.0, "H": 2158.0, "L": 109.0, "R": 1036.0, "T": 127.0, "B": 2025.0, "cs": 831.0, "g": 161.0, "gs": "rope"},
	{"id": "court", "name": "Court", "W": 1147.0, "H": 2143.9, "L": 132.0, "R": 1016.0, "T": 129.0, "B": 1965.9, "cs": 801.0, "g": 154.0, "gs": "white"},
	{"id": "cyberbox", "name": "Cyber Box", "W": 1147.0, "H": 2146.6, "L": 132.0, "R": 1015.0, "T": 121.0, "B": 1969.6, "cs": 791.0, "g": 153.0, "gs": "black"},
	{"id": "realmadrid", "name": "Real Madrid", "W": 1216.0, "H": 2035.4, "L": 218.0, "R": 996.0, "T": 112.0, "B": 1903.4, "cs": 809.0, "g": 135.0, "gs": "black"},
	{"id": "psg", "name": "Paris SG", "W": 1216.0, "H": 2018.9, "L": 228.0, "R": 987.0, "T": 129.0, "B": 1848.9, "cs": 746.0, "g": 135.0, "gs": "red"},
	{"id": "acmilan", "name": "AC Milan", "W": 1216.0, "H": 2035.4, "L": 218.0, "R": 996.0, "T": 112.0, "B": 1903.4, "cs": 809.0, "g": 135.0, "gs": "white"},
	{"id": "barcelona", "name": "FC Barcelona", "W": 1216.0, "H": 2034.5, "L": 217.0, "R": 996.0, "T": 113.0, "B": 1900.5, "cs": 808.0, "g": 135.0, "gs": "gold"},
	{"id": "persepolis", "name": "Persepolis", "W": 1290.0, "H": 2148.4, "L": 232.0, "R": 1056.0, "T": 151.0, "B": 2007.4, "cs": 862.0, "g": 135.0, "gs": "white"},
	{"id": "esteghlal", "name": "Esteghlal", "W": 1216.0, "H": 2032.7, "L": 218.0, "R": 997.0, "T": 112.0, "B": 1891.7, "cs": 773.0, "g": 135.0, "gs": "gold"},
	{"id": "mancity", "name": "Man City", "W": 1216.0, "H": 2034.2, "L": 218.0, "R": 996.0, "T": 114.0, "B": 1900.2, "cs": 805.0, "g": 135.0, "gs": "red"}
]
## Piece catalog: the NX8 build's groups/order/names first (index_v4_backup.html: lux, club, nat, spt, gal; art res://assets/nx8/teams),
## then the v4 categories NX8 lacks (vip, car, elite, emb, leg, chrome; art res://assets/g/teams).
const CATS := [["lux", "Luxury", ["Lamborghini", "Ferrari", "Porsche", "Mercedes-Benz", "BMW", "Aston Martin", "Rolls-Royce", "Bentley", "Maserati", "Bugatti", "McLaren", "Lexus", "Tesla", "Volvo", "Land Rover", "Audi", "Cadillac", "Alfa Romeo", "Pagani", "Koenigsegg"]], ["club", "Clubs", ["Persepolis", "Esteghlal", "Sepahan", "Tractor", "Foolad", "Zob Ahan", "Nassaji Mazandaran", "Sanat Naft Abadan", "Aluminium Arak", "Mes Rafsanjan", "Paykan", "Malavan", "Gol Gohar Sirjan", "Chadormalu", "Shahin Bushehr", "Mes Kerman", "Kheybar Khorramabad", "Arvand Khorramshahr", "Real Madrid 1902", "Barcelona 1899", "Bayern 1900", "AC Milan 1899", "Juventus 1897", "Inter 1908", "Liverpool", "Manchester City", "Chelsea", "Arsenal", "Manchester United", "Atlético Madrid", "Inter Milan", "AC Milan", "Juventus", "FC Barcelona", "Real Madrid", "Bayern Munich", "Borussia Dortmund", "Paris Saint-Germain", "Marseille", "AS Roma", "Napoli", "Lazio", "Atalanta", "Fiorentina", "Sevilla", "Benfica", "Sporting CP", "FC Porto", "Ajax", "PSV Eindhoven", "Bayer Leverkusen", "RB Leipzig", "Gladbach", "Lille", "West Ham United", "Leicester City", "FC Basel", "Celtic", "Galatasaray", "Beşiktaş", "Shakhtar Donetsk", "Zenit", "Red Bull Salzburg", "Dinamo Zagreb", "Inter Miami", "Wolfsburg", "Tottenham", "Rangers", "Monaco", "Aston Villa", "Olympique Lyonnais", "Al Hilal"]], ["nat", "National", ["Argentina", "Brazil", "Germany", "France", "Portugal", "Spain", "England", "Italy", "Netherlands", "Uruguay", "Mexico", "Belgium", "Poland", "Switzerland", "Croatia", "Morocco", "Senegal", "South Korea", "Japan", "USA", "Argentina II", "Brazil II", "France II", "Germany II", "England II", "Italy II", "Spain II", "Portugal II", "Netherlands II", "Belgium II", "Sweden", "Denmark", "Poland II", "Switzerland II", "Croatia II", "Serbia", "Mexico II", "USA II", "Uruguay II", "Colombia", "Chile", "Ecuador", "Algeria", "Morocco II", "Nigeria", "Cameroon", "Ghana", "Senegal II", "Ivory Coast", "Tunisia", "Egypt", "Japan II", "South Korea II", "Australia", "New Zealand", "Iran", "Saudi Arabia", "Qatar", "Iraq", "UAE", "Lebanon"]], ["spt", "Sport", ["Nike", "Adidas", "Puma", "Under Armour", "Reebok", "New Balance", "ASICS", "Mizuno", "Wilson", "Converse", "Jordan", "Skechers", "EA7", "The North Face", "Columbia", "Speedo", "Arena", "Wilson Tennis", "Dunlop", "Head"]], ["gal", "Girls", ["Chanel", "Louis Vuitton", "Dior", "Gucci", "Yves Saint Laurent", "Prada", "MAC", "Victoria's Secret", "Sephora", "Estée Lauder", "Lancôme", "Zara", "H&M", "Uniqlo", "Pandora", "Kate Spade", "Coach", "Cartier", "Tiffany & Co.", "PINK"]], ["vip", "VIP", ["Nova Blue", "Aurum Crest", "Emerald Core", "Specter Wings", "Infernal Edge", "Timber Blaze", "Chrome Vortex", "Crimson Pulse", "Thunder Gold", "Jade Marble", "Kakero Noir", "Kakero Frost"]], ["car", "Cars", ["Lamborghini", "Ferrari", "Rolls-Royce", "Mercedes-Benz", "BMW", "Porsche", "Maserati", "Aston Martin", "Bentley", "Bugatti", "Lexus", "Cadillac", "McLaren", "Tesla"]], ["elite", "Elite", ["NX Prime", "Real Madrid", "Barcelona", "Juventus", "Liverpool", "Manchester United", "Paris SG", "Bayern Munich", "Atletico Madrid", "Inter Milan", "AC Milan", "Chelsea", "Manchester City", "Arsenal", "Tottenham", "Dortmund", "Leverkusen", "Napoli", "Roma", "Lazio", "Fiorentina", "Monaco", "Marseille", "Benfica", "Porto", "Sporting CP", "Galatasaray", "Besiktas", "Fenerbahce", "Ajax", "Al Hilal", "Al Nassr", "Al Ittihad", "Al Ain", "Al Ahly", "Zamalek"]], ["emb", "Emblems", ["Golden Lion", "Shadow Wolf", "Azure Dragon", "Phoenix", "Viper", "Silver Eagle", "Iron Bull", "Frost Crown", "Scorpion", "Tide Shark", "Evergreen", "Royal Fleur", "Compass", "NX Gold", "Polaris", "Grizzly"]], ["leg", "Legends", ["Inferno Scorpion", "Dire Wolf", "Samurai Sun", "Venom Dragon", "Bermuda", "Magma Golem"]], ["chrome", "Chrome", ["Mercedes Chrome", "BMW Chrome", "Toyota Chrome", "Ferrari Chrome", "Lambo Chrome", "Porsche Chrome", "Tesla Chrome", "Audi Chrome"]]]
## Disc art audit (tests/tools/disc_audit.py, 2026-11-13): discs that are not a clean round coin (gear rims cut by the
## alpha circle, off-centre art — e.g. Al Nassr — or logo-on-black "chrome" art) are hidden from the game and shop.
## Their ids keep their index (owned lists / server rows stay valid); a profile equipped with one falls back to club0.
const REMOVED_TEAMS := ["chrome0", "chrome1", "chrome2", "chrome3", "chrome4", "chrome5", "chrome6", "chrome7",
	"elite0", "elite1", "elite2", "elite3", "elite4", "elite5", "elite6", "elite7", "elite8", "elite9", "elite10", "elite11",
	"elite12", "elite13", "elite14", "elite15", "elite16", "elite17", "elite18", "elite19", "elite20", "elite21", "elite22",
	"elite23", "elite24", "elite25", "elite26", "elite27", "elite28", "elite29", "elite30", "elite31", "elite32", "elite33",
	"elite34", "elite35"]
const NX8_CATS := ["lux", "club", "nat", "spt", "gal"]
const CAT_ORDER := ["lux", "club", "nat", "spt", "gal", "vip", "car", "elite", "emb", "leg", "chrome"]
const CAT_FA := {"lux": "لوکس", "club": "باشگاه", "nat": "ملی", "spt": "ورزشی", "gal": "بانوان", "vip": "VIP", "car": "خودرو", "elite": "الیت", "emb": "نشان", "leg": "افسانه", "chrome": "کروم"}
## Formations (user's 9-formation sheet). Entry: [name_fa, name_en, rows (legacy, unused), pts]
## pts: [depth, lateral] per disc — depth 0 = own goal line … 1 = halfway line; lateral 0..1 across the pitch
## (left->right for the bottom side; the top side is the mirror image). Spaced for the current disc radius (fm check: min gap >= 13 px).
const FORMS := [
	["الماس", "Diamond", [], [[0.14, 0.5], [0.39, 0.20], [0.39, 0.80], [0.76, 0.36], [0.76, 0.64]]],
	["عقاب", "Eagle", [], [[0.14, 0.5], [0.36, 0.20], [0.36, 0.80], [0.56, 0.5], [0.86, 0.5]]],
	["موج", "Wave", [], [[0.30, 0.27], [0.30, 0.73], [0.62, 0.06], [0.62, 0.5], [0.62, 0.94]]],
	["ماه", "Moon", [], [[0.18, 0.5], [0.38, 0.18], [0.38, 0.82], [0.64, 0.04], [0.64, 0.96]]],
	["دیوانه", "Crazy", [], [[0.62, 0.5], [0.86, 0.0], [0.86, 0.31], [0.86, 0.69], [0.86, 1.0]]],
	["لبه", "Edge", [], [[0.11, 0.5], [0.37, 0.5], [0.63, 0.5], [0.86, 0.12], [0.86, 0.88]]],
	["نیش", "Sting", [], [[0.13, 0.5], [0.50, 0.08], [0.50, 0.92], [0.88, 0.08], [0.88, 0.92]]],
	["بازو", "Arm", [], [[0.13, 0.5], [0.56, 0.12], [0.56, 0.5], [0.56, 0.88], [0.88, 0.88]]],
	["حمله همه جانبه", "All-out Attack", [], [[0.13, 0.5], [0.72, 0.30], [0.72, 0.70], [0.88, 0.04], [0.88, 0.96]]],
]
const TRAILS := [
	{"k": "bolt", "c": ["#19b4ff", "#8fe6ff", "#ffffff"]},
	{"k": "prism", "c": ["#ff7bd5", "#7bd7ff", "#ffffff"]},
	{"k": "wave", "c": ["#2fe0d0", "#9ff7ef", "#ffffff"]},
	{"k": "star", "c": ["#5cb6ff", "#bfe3ff", "#ffffff"]},
	{"k": "smoke", "c": ["#e8ecf2", "#9aa3b0", "#ffffff"]},
	{"k": "rainbow", "c": ["#ff5b5b", "#ffd23a", "#5bff8a", "#5bd0ff", "#c05bff"]},
	{"k": "neon", "c": ["#4dff2a", "#b6ff9a", "#ffffff"]},
	{"k": "yin", "c": ["#ffffff", "#9b5cff", "#000000"]},
	{"k": "fire", "c": ["#ff8a1f", "#ffd24a", "#fff3c4"]},
	{"k": "blade", "c": ["#ff2b3a", "#ff8a92", "#ffffff"]},
	{"k": "ghost", "c": ["#dbe7ff", "#8fb0ff", "#ffffff"]},
	{"k": "ember", "c": ["#ff6a1f", "#ffb347", "#fff0c8"]},
	{"k": "plasma", "c": ["#2f8bff", "#7fc6ff", "#ffffff"]},
	{"k": "ghost", "c": ["#d9915b", "#f2c9a0", "#fff4e6"]},
	{"k": "star", "c": ["#2f7bff", "#8fd0ff", "#ffffff"]},
	{"k": "wave", "c": ["#9b5cff", "#e0b8ff", "#ffffff"]},
	{"k": "fire", "c": ["#e0a82e", "#ffe08a", "#fff7d6"]},
	{"k": "bolt", "c": ["#2f6bff", "#7fb4ff", "#ffffff"]},
	{"k": "neon", "c": ["#2f8bff", "#e8b84a", "#ffffff"]},
	{"k": "prism", "c": ["#1fd6a0", "#3b9bff", "#ffffff"]},
	{"k": "blade", "c": ["#ff2b3a", "#ff8a92", "#ffffff"]},
	{"k": "plasma", "c": ["#18d8c0", "#9ff5e6", "#ffffff"]},
	{"k": "ember", "c": ["#2f5bff", "#ffc83a", "#fff3c4"]},
	{"k": "yin", "c": ["#ffffff", "#e0a82e", "#000000"]},
	{"k": "smoke", "c": ["#ff4a4a", "#9aa3b0", "#ffffff"]},
	{"k": "star", "c": ["#e0a82e", "#fff0b0", "#ffffff"]},
	{"k": "plasma", "c": ["#2f8bff", "#c0c8d8", "#ffffff"]},
	{"k": "ghost", "c": ["#9b5cff", "#ffffff", "#ffffff"]},
	{"k": "neon", "c": ["#4dff2a", "#c0c8d8", "#ffffff"]},
	{"k": "blade", "c": ["#e8b84a", "#2f6bff", "#ffffff"]},
	{"k": "fire", "c": ["#ff2b3a", "#ff8a92", "#ffffff"]},
	{"k": "ember", "c": ["#ff8a1f", "#ffd24a", "#ffffff"]},
	{"k": "wave", "c": ["#3b9bff", "#2fe08a", "#ffffff"]},
	{"k": "prism", "c": ["#ff4a7a", "#9b5cff", "#ffffff"]},
	{"k": "bolt", "c": ["#2f6bff", "#ffffff", "#ffffff"]},
	{"k": "star", "c": ["#ffd56b", "#ffffff", "#ffffff"]}
]
const BALL_NAMES := ["Bolt", "Prism", "Wave", "Starlight", "Classic", "Rainbow", "Neon", "Yin", "Fire", "Blade", "Ghost", "Ember", "Plasma", "Noir Copper", "Space Modern", "Purple Sky", "Black Lux", "Electron", "Cobalt Gold", "Aurora", "Crimson", "Teal Storm", "Royal Gold", "Gold Rush", "Classic Red", "Luxury", "Noir Chrome", "Violet Strike", "Emerald Edge", "Royal Blue Gold", "Crimson Noir", "Blaze Orange", "Aqua Wave", "Sunset Pro", "Elite Cobalt", "Crown Luxury"]
const FIELD_FX := {
	"pitch": {"k": 1, "c": ["#ffffff", "#d8ffb0", "#7bff5a"], "g": 0.0},
	"forest": {"k": 2, "c": ["#6fd36b", "#b8f5a0", "#2e8b3a"], "g": 130.0},
	"ice": {"k": 1, "c": ["#e8fbff", "#9fe8ff", "#ffffff"], "g": 30.0},
	"ocean": {"k": 4, "c": ["#bff3ff", "#5cd0ff", "#ffffff"], "g": -140.0},
	"street": {"k": 5, "c": ["#ff2bd6", "#ffe14a", "#2bf0ff"], "g": 0.0},
	"streetarena": {"k": 5, "c": ["#ffb02b", "#ff3b6b", "#ffffff"], "g": 0.0},
	"lava": {"k": 0, "c": ["#ff5a1f", "#ffb347", "#ffe08a"], "g": -220.0},
	"stadium": {"k": 1, "c": ["#ffd86b", "#ffffff", "#ffe9a8"], "g": 0.0},
	"checker": {"k": 3, "c": ["#ffffff", "#9aa3b0", "#ff4040"], "g": 0.0},
	"futsal": {"k": 5, "c": ["#ffcf8a", "#ffffff", "#ffa14a"], "g": 0.0},
	"arena": {"k": 5, "c": ["#7fb8ff", "#ffffff", "#3b7bff"], "g": 0.0},
	"arena2": {"k": 1, "c": ["#c79bff", "#ffffff", "#7b4bff"], "g": 0.0},
	"desert": {"k": 0, "c": ["#e8c689", "#c99a54", "#fff0c8"], "g": 60.0},
	"grove": {"k": 0, "c": ["#d8ff6a", "#ffffa0", "#9cf06a"], "g": -30.0},
	"pool": {"k": 0, "c": ["#9fe9ff", "#e6fbff", "#4cc7ff"], "g": 380.0},
	"neon": {"k": 5, "c": ["#7dff3a", "#d6ff9a", "#ffffff"], "g": 0.0},
	"royal": {"k": 1, "c": ["#ffd86b", "#fff3c4", "#ff9a3a"], "g": 0.0},
	"mahogany": {"k": 1, "c": ["#ffcf8a", "#fff0c8", "#d9923a"], "g": -20.0},
	"leather": {"k": 0, "c": ["#d9a066", "#ffd9a0", "#8a5a2a"], "g": -30.0},
	"aqua": {"k": 4, "c": ["#bff3ff", "#5cd0ff", "#ffffff"], "g": -150.0},
	"asphalt": {"k": 5, "c": ["#ffe14a", "#ffffff", "#ffb02b"], "g": 0.0},
	"court": {"k": 5, "c": ["#ffffff", "#ffcf8a", "#4aa8ff"], "g": 0.0},
	"cyberbox": {"k": 5, "c": ["#ff3b3b", "#3b8bff", "#ffffff"], "g": 0.0},
	"realmadrid": {"k": 1, "c": ["#ffffff", "#ffd86b", "#3b6bff"], "g": 0.0},
	"psg": {"k": 5, "c": ["#ff2b3a", "#3b6bff", "#ffffff"], "g": 0.0},
	"acmilan": {"k": 5, "c": ["#ff2b3a", "#ffffff", "#111111"], "g": 0.0},
	"barcelona": {"k": 5, "c": ["#ff2b5a", "#3b6bff", "#ffd86b"], "g": 0.0},
	"persepolis": {"k": 5, "c": ["#ff2b3a", "#ffd86b", "#ffffff"], "g": 0.0},
	"esteghlal": {"k": 1, "c": ["#3b8bff", "#ffffff", "#ffd86b"], "g": 0.0},
	"mancity": {"k": 1, "c": ["#7fd0ff", "#ffffff", "#3b8bff"], "g": 0.0}
}
const VIP_PRICES := [260, 275, 290, 255, 300, 265, 280, 270, 0, 295, 285, 250]

const RARITY := [{"n": "COMMON", "c": "#8ea3d6"}, {"n": "RARE", "c": "#4fe3ff"}, {"n": "EPIC", "c": "#b46bff"}, {"n": "LEGENDARY", "c": "#ffd257"}]
const LEAGUES := [["BRONZE", 0], ["SILVER", 300], ["GOLD", 800], ["PLATINUM", 1600], ["DIAMOND", 3000], ["NEXORA", 5000]]
const LEAGUE_FA := {"BRONZE": "برنز", "SILVER": "نقره", "GOLD": "طلا", "PLATINUM": "پلاتین", "DIAMOND": "الماس", "NEXORA": "نکسورا"}

const ACHS := [
	{"id": "first", "name": "اولین قدم", "desc": "یک بازی انجام بده", "icon": "x_ball", "max": 1, "coins": 100, "gems": 0},
	{"id": "win5", "name": "برنده", "desc": "۵ بازی ببر", "icon": "x_medal", "max": 5, "coins": 250, "gems": 0},
	{"id": "goals25", "name": "گلزن", "desc": "۲۵ گل بزن", "icon": "x_statue", "max": 25, "coins": 300, "gems": 0},
	{"id": "streak3", "name": "شکست‌ناپذیر", "desc": "۳ برد پشت سر هم", "icon": "x_star", "max": 3, "coins": 350, "gems": 0},
	{"id": "cup1", "name": "قهرمان", "desc": "جام نکسورا را ببر", "icon": "x_trophy", "max": 1, "coins": 500, "gems": 0},
	{"id": "collect", "name": "کلکسیونر", "desc": "۱۵ دیسک ویژه باز کن", "icon": "x_team", "max": 15, "coins": 400, "gems": 0},
	{"id": "win25", "name": "اسطوره", "desc": "۲۵ بازی ببر", "icon": "x_crown", "max": 25, "coins": 800, "gems": 0},
	{"id": "gold", "name": "لیگ طلا", "desc": "به ۸۰۰ جام برس", "icon": "x_shield", "max": 800, "coins": 600, "gems": 0},
]
const DAILY := [
	{"coins": 100, "gems": 0}, {"coins": 150, "gems": 0}, {"coins": 250, "gems": 0}, {"coins": 300, "gems": 0},
	{"coins": 400, "gems": 0}, {"coins": 450, "gems": 0}, {"coins": 800, "gems": 0},
]
## Offline match modes (Setup.tsx MULT table used by App.tsx onFinish)
const MULT := {"quick": 1.0, "cup": 2.0, "galaxy": 3.0, "train": 0.3, "local": 0.0}

## Everything here is static so scripts can also use it without the autoload
## (headless -s tests / --check-only): `const D := preload("res://src/core/data.gd")` then D.FIELDS, D.team_by_id(...).
static var TEAMS: Array = []           # [{id,cat,name,idx}]
static var CAT_LABEL: Dictionary = {}
static var _team_idx: Dictionary = {}
static var _tex_cache: Dictionary = {}
## Server disc catalog (NET fills: Data.disc_catalog[id] = {power, accuracy, price_gems}); falls back like net/discs.tsx
static var disc_catalog: Dictionary = {}

static func _static_init() -> void:
	for c in CATS:
		var k: String = c[0]
		CAT_LABEL[k] = c[1]
		var l: Array = c[2]
		for i in l.size():
			var t := {"id": k + str(i), "cat": k, "name": l[i], "idx": i}
			if REMOVED_TEAMS.has(t.id): continue
			_team_idx[t.id] = TEAMS.size()
			TEAMS.append(t)

# ---------------- data.ts helpers ----------------
static func team_price(t: Dictionary) -> int:
	var cat: String = t.cat
	if cat == "vip":
		var v: int = VIP_PRICES[t.idx] if t.idx < VIP_PRICES.size() else 0
		return v if v != 0 else 250
	if cat == "club" or cat == "nat": return 0
	if cat == "leg": return 520
	if cat == "emb": return 220
	if cat == "elite": return 0 if t.idx == 0 else 160
	if cat == "chrome": return 180
	return 120

static func ball_price(i: int) -> int:
	return 0 if i < 6 else 60 + (i % 7) * 20

static func field_price(i: int) -> int:
	return 0 if i < 5 else 80 + ((i - 1) % 5) * 20

## formation slots: Array of [nx, ny] (float64 — Vector2 is float32 and would break physics parity)
## nx = lateral 0..1 (engine insets it by the disc radius), ny = distance from own goal line as a fraction of the pitch length.
static func slots(fi: int) -> Array:
	var o: Array = []
	var fm: Array = FORMS[clampi(fi, 0, FORMS.size() - 1)]
	if fm.size() > 3:
		for pt in fm[3]:
			o.append([float(pt[1]), 0.02 + float(pt[0]) * 0.48])
		return o
	for row in fm[2]:
		var ny: float = row[0]
		var c: int = int(row[1])
		for i in c:
			var nx: float
			if c == 1: nx = 0.5
			elif c == 2: nx = 0.27 + 0.46 * i
			else: nx = 0.17 + 0.33 * i
			o.append([nx, ny])
	return o

# ---------------- util.ts ----------------
static func team_key(t: Dictionary) -> String:
	return String(t.cat) + str(t.idx).pad_zeros(2)

static func team_by_id(id: String) -> Dictionary:
	return TEAMS[_team_idx[id]] if _team_idx.has(id) else TEAMS[_team_idx.get("club0", 0)]

static func team_removed(id: String) -> bool: return REMOVED_TEAMS.has(id)

static func hash32(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h

static func _i32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v

static func card_stats(seed: String) -> Dictionary:
	var h := hash32(seed)
	var hs := _i32(h)
	return {"power": 60 + (h % 37), "control": 55 + ((hs >> 6) % 42), "speed": 58 + ((hs >> 12) % 40), "spin": 50 + ((hs >> 18) % 46)}

static func rarity(t: Dictionary) -> int:
	var c: String = t.cat
	if c == "vip" or c == "leg": return 3
	if c == "lux" or c == "gal" or c == "car" or c == "emb" or c == "chrome": return 2
	if c == "spt" or c == "elite": return 1
	return 0

# ---------------- store.tsx level / league ----------------
static func level(xp: int) -> Dictionary:
	var l := 1
	var need := 100
	var x := xp
	while x >= need:
		x -= need
		l += 1
		need = int(round(need * 1.25))
	return {"level": l, "cur": x, "need": need}

static func league(t: int) -> Dictionary:
	var i := 0
	while i + 1 < LEAGUES.size() and t >= LEAGUES[i + 1][1]:
		i += 1
	return {"name": LEAGUES[i][0], "idx": i, "from": LEAGUES[i][1], "to": LEAGUES[i + 1][1] if i + 1 < LEAGUES.size() else LEAGUES[i][1] + 2000}

# ---------------- meta.ts ----------------
static func ach_cur(a: Dictionary, p: Dictionary) -> int:
	match String(a.id):
		"first": return int(p.played)
		"win5", "win25": return int(p.wins)
		"goals25": return int(p.goalsFor)
		"streak3": return int(p.bestStreak)
		"cup1": return int(p.cupsWon)
		"collect":
			var n := 0
			for id in p.ownedTeams:
				var s := String(id)
				if not s.begins_with("club") and not s.begins_with("nat"): n += 1
			return n
		"gold": return int(p.trophies)
	return 0

## Item: {kind:"team"|"ball"|"field", id, name, price, img(path), rar}
static func all_items(p: Dictionary) -> Array:
	var out: Array = []
	# discs are bought with gems from the online catalog, not with coins (meta.ts `if (false)`)
	for i in 36:
		if ball_price(i) > 0 and not _has_int(p.ownedBalls, i):
			out.append({"kind": "ball", "id": i, "name": BALL_NAMES[i], "price": ball_price(i), "img": BALL_IMG["b" + str(i)], "rar": 2 if ball_price(i) > 140 else 1})
	for i in FIELDS.size():
		if field_price(i) > 0 and not _has_int(p.ownedFields, i):
			var f: Dictionary = FIELDS[i]
			out.append({"kind": "field", "id": i, "name": f.name, "price": field_price(i), "img": FIELD_THUMB[f.id], "rar": 2 if field_price(i) > 140 else 1})
	return out

static func _has_int(a: Array, v: int) -> bool:
	for x in a:
		if int(x) == v: return true
	return false

## returns the profile patch that grants the item (meta.ts grant)
static func grant(it: Dictionary, q: Dictionary) -> Dictionary:
	if it.kind == "team":
		var a: Array = q.ownedTeams.duplicate(); a.append(it.id); return {"ownedTeams": a}
	if it.kind == "ball":
		var b: Array = q.ownedBalls.duplicate(); b.append(int(it.id)); return {"ownedBalls": b}
	var c: Array = q.ownedFields.duplicate(); c.append(int(it.id)); return {"ownedFields": c}

static func daily_deals(p: Dictionary, n := 4) -> Array:
	var items := all_items(p)
	var day := int(floor(Time.get_unix_time_from_system() / 86400.0))
	var h := (day * 2654435761) & 0xFFFFFFFF
	var a := items.duplicate()
	var i := a.size() - 1
	while i > 0:
		h = (h ^ (h << 13)) & 0xFFFFFFFF
		h = h ^ (h >> 17)
		h = (h ^ (h << 5)) & 0xFFFFFFFF
		var r := float(h % 10000) / 10000.0
		var j := int(floor(r * (i + 1)))
		var t = a[i]; a[i] = a[j]; a[j] = t
		i -= 1
	var out: Array = []
	for k in mini(n, a.size()):
		var it: Dictionary = a[k].duplicate()
		it.price = int(round(it.price * 0.7 / 5.0)) * 5
		out.append(it)
	return out

## ChestPrize {item?, coins, gems}
static func roll_chest(p: Dictionary, premium: bool) -> Dictionary:
	var items: Array = []
	for it in all_items(p):
		if not premium or it.rar >= 2: items.append(it)
	var r := randf()
	if items.size() and r < (0.75 if premium else 0.4):
		var w: Array = []
		var sum := 0.0
		for it in items:
			var x: float = it.rar if premium else 4 - it.rar
			w.append(x); sum += x
		var y := randf() * sum
		for k in items.size():
			y -= w[k]
			if y <= 0: return {"item": items[k], "coins": 60 if premium else 20, "gems": 0}
	return {"coins": (320 + int(round(randf() * 200))) if premium else (80 + int(round(randf() * 120))), "gems": 0}

# ---------------- disc stats / launch (Setup.tsx buildLaunch + net/discs.tsx discStats) ----------------
static func disc_stats(id: String) -> Dictionary:
	if disc_catalog.has(id):
		var d: Dictionary = disc_catalog[id]
		return {"power": float(d.get("power", 5)), "accuracy": float(d.get("accuracy", 5))}
	if id == "":
		return {"power": 5.0, "accuracy": 5.0}
	# offline / unloaded catalog: deterministic per-category spread so every disc
	# really feels different (club 4-6 … legendary 9-10); matches the UI stat bars.
	var cat := ""
	var idx := 0
	if _team_idx.has(id):
		var t: Dictionary = TEAMS[_team_idx[id]]
		cat = String(t.cat)
		idx = int(t.idx)
	var p := 5.0
	var a := 5.0
	match cat:
		"club":
			p = 4.0 + (idx % 3); a = 4.0 + ((idx * 7) % 3)
		"nat":
			p = 5.0 + (idx % 3); a = 5.0 + ((idx * 5) % 3)
		"elite":
			p = 6.0 + (idx % 3); a = 6.0 + ((idx * 3) % 3)
		"spt", "gal":
			p = 6.0 + (idx % 2); a = 6.0 + ((idx * 4) % 3)
		"car":
			p = 7.0 + (idx % 2); a = 5.0 + ((idx * 6) % 3)
		"lux", "emb":
			p = 6.0 + (idx % 3); a = 6.0 + ((idx * 7) % 3)
		"chrome":
			p = 7.0 + (idx % 2); a = 6.0 + ((idx * 8) % 2)
		"vip":
			p = 8.0 + (idx % 2); a = 7.0 + ((idx * 5) % 2)
		"leg":
			p = 9.0 + (idx % 2); a = 8.0 + ((idx * 5) % 2)
	return {"power": p, "accuracy": a}

static func opp_pool() -> Array:
	var o: Array = []
	for t in TEAMS:
		if t.cat == "club" or t.cat == "nat" or t.cat == "elite": o.append(t)
	return o

static func pick_opp() -> Dictionary:
	var p := opp_pool()
	return p[randi() % p.size()]

static func _boosted(t: Dictionary) -> bool:
	return t.cat == "vip" or t.cat == "leg"

## Port of Setup.tsx buildLaunch. mode: quick|local|cup|galaxy|train. opt: {lvl, rule:"g3"|"g5"|"t3", tt, opp(team dict), stage}
## Returns Launch {cfg, teams:[me, opp], names:[a,b], mode, stage} — pass it to Nav.go("match", launch).
static func build_launch(mode: String, p: Dictionary, opt: Dictionary) -> Dictionary:
	var me := team_by_id(String(p.team))
	var opp: Dictionary = opt.get("opp", pick_opp())
	var opp_form := randi() % FORMS.size()
	var ai := mode != "local"
	var lvl := int(opt.get("lvl", 1))
	var rule := String(opt.get("rule", "g3"))
	var limit := 5 if rule == "g5" else 3
	var match_time := 180 if rule == "t3" else 0
	var tt := int(opt.get("tt", 15))
	var stage := int(opt.get("stage", 0))
	if mode == "cup": lvl = mini(2, stage); limit = 3; match_time = 0
	if mode == "galaxy": lvl = 2; match_time = 120; limit = 99
	if mode == "train": lvl = 0; tt = 0
	var cfg := {
		"field": int(p.field), "ball": int(p.ball), "forms": [int(p.form), opp_form if ai else int(p.form)], "ai": ai, "ai_lvl": lvl,
		"limit": limit, "match_time": match_time, "turn_time": tt, "vip": [_boosted(me), _boosted(opp)], "first": 0,
		"stats": [disc_stats(me.id), disc_stats(opp.id)], "teams": [me.id, opp.id],
	}
	return {"cfg": cfg, "teams": [me, opp], "names": [String(p.name), String(opp.name) if ai else "بازیکن ۲"], "mode": mode, "stage": stage}

# ---------------- textures ----------------
static func tex(path: String) -> Texture2D:
	if path == "": return null
	var t = _tex_cache.get(path)
	if t != null: return t
	if not ResourceLoader.exists(path): return null
	t = load(path) as Texture2D
	_tex_cache[path] = t
	return t

## NX8 art first; any id NX8 lacks falls back to the v4 art in assets/g/teams
static func team_img_path(id: String) -> String:
	var k := team_key(team_by_id(id))
	var p: String = TEAM_IMG.get(k, "")
	if p == "" or not ResourceLoader.exists(p):
		var old := "res://assets/g/teams/%s.webp" % k
		if ResourceLoader.exists(old): return old
	return p
static func team_tex(id: String) -> Texture2D: return tex(team_img_path(id))
static func ball_tex(i: int) -> Texture2D: return tex(BALL_IMG.get("b" + str(i), BALL_IMG["b0"]))
## shop / picker card art for a ball (NX8 s<i>.webp thumbnails, else the sphere texture)
static func ball_thumb(i: int) -> Texture2D: return tex(BALL_THUMB.get("b" + str(i), BALL_IMG.get("b" + str(i), BALL_IMG["b0"])))
static func field_tex(i: int) -> Texture2D: return tex(FIELD_IMG.get(FIELDS[clampi(i, 0, FIELDS.size() - 1)].id, ""))
static func field_thumb(i: int) -> Texture2D: return tex(FIELD_THUMB.get(FIELDS[clampi(i, 0, FIELDS.size() - 1)].id, ""))
static func goal_tex(gs: String) -> Texture2D: return tex(GOAL_IMG.get(gs, GOAL_IMG["white"]))
static func arrow_tex(k: String) -> Texture2D: return tex(ARROW_IMG.get(k, ""))
static func oracle_tex(k: String) -> Texture2D: return tex(ORACLE.get(k, ORACLE["idle"]))
## ui(name): assets.ts UI map (webp/jpg/png); unknown keys fall back to res://assets/g/ui/<name>.webp
static func ui(name: String) -> Texture2D: return tex(UI.get(name, "res://assets/g/ui/%s.webp" % name))
static func ui2(name: String) -> Texture2D: return tex(UI2.get(name, "res://assets/g/ui2/%s.webp" % name))
static func menu(name: String) -> Texture2D: return tex(MENU.get(name, "res://assets/g/menu/%s.webp" % name))

# ---------------- asset maps (same keys as RN) ----------------
## NX8 piece art (assets/nx8/teams) for the NX8 groups; v4 art (assets/g/teams) for the rest.
const TEAM_IMG := {
	"club64": "res://assets/nx8/teams/club64.webp",
	"club65": "res://assets/nx8/teams/club65.webp",
	"club66": "res://assets/nx8/teams/club66.webp",
	"club67": "res://assets/nx8/teams/club67.webp",
	"club68": "res://assets/nx8/teams/club68.webp",
	"club69": "res://assets/nx8/teams/club69.webp",
	"club70": "res://assets/nx8/teams/club70.webp",
	"club71": "res://assets/nx8/teams/club71.webp",
	"nat60": "res://assets/nx8/teams/nat60.webp",
	"lux00": "res://assets/nx8/teams/lux00.webp",
	"lux01": "res://assets/nx8/teams/lux01.webp",
	"lux02": "res://assets/nx8/teams/lux02.webp",
	"lux03": "res://assets/nx8/teams/lux03.webp",
	"lux04": "res://assets/nx8/teams/lux04.webp",
	"lux05": "res://assets/nx8/teams/lux05.webp",
	"lux06": "res://assets/nx8/teams/lux06.webp",
	"lux07": "res://assets/nx8/teams/lux07.webp",
	"lux08": "res://assets/nx8/teams/lux08.webp",
	"lux09": "res://assets/nx8/teams/lux09.webp",
	"lux10": "res://assets/nx8/teams/lux10.webp",
	"lux11": "res://assets/nx8/teams/lux11.webp",
	"lux12": "res://assets/nx8/teams/lux12.webp",
	"lux13": "res://assets/nx8/teams/lux13.webp",
	"lux14": "res://assets/nx8/teams/lux14.webp",
	"lux15": "res://assets/nx8/teams/lux15.webp",
	"lux16": "res://assets/nx8/teams/lux16.webp",
	"lux17": "res://assets/nx8/teams/lux17.webp",
	"lux18": "res://assets/nx8/teams/lux18.webp",
	"lux19": "res://assets/nx8/teams/lux19.webp",
	"club00": "res://assets/nx8/teams/club00.webp",
	"club01": "res://assets/nx8/teams/club01.webp",
	"club02": "res://assets/nx8/teams/club02.webp",
	"club03": "res://assets/nx8/teams/club03.webp",
	"club04": "res://assets/nx8/teams/club04.webp",
	"club05": "res://assets/nx8/teams/club05.webp",
	"club06": "res://assets/nx8/teams/club06.webp",
	"club07": "res://assets/nx8/teams/club07.webp",
	"club08": "res://assets/nx8/teams/club08.webp",
	"club09": "res://assets/nx8/teams/club09.webp",
	"club10": "res://assets/nx8/teams/club10.webp",
	"club11": "res://assets/nx8/teams/club11.webp",
	"club12": "res://assets/nx8/teams/club12.webp",
	"club13": "res://assets/nx8/teams/club13.webp",
	"club14": "res://assets/nx8/teams/club14.webp",
	"club15": "res://assets/nx8/teams/club15.webp",
	"club16": "res://assets/nx8/teams/club16.webp",
	"club17": "res://assets/nx8/teams/club17.webp",
	"club18": "res://assets/nx8/teams/club18.webp",
	"club19": "res://assets/nx8/teams/club19.webp",
	"club20": "res://assets/nx8/teams/club20.webp",
	"club21": "res://assets/nx8/teams/club21.webp",
	"club22": "res://assets/nx8/teams/club22.webp",
	"club23": "res://assets/nx8/teams/club23.webp",
	"club24": "res://assets/nx8/teams/club24.webp",
	"club25": "res://assets/nx8/teams/club25.webp",
	"club26": "res://assets/nx8/teams/club26.webp",
	"club27": "res://assets/nx8/teams/club27.webp",
	"club28": "res://assets/nx8/teams/club28.webp",
	"club29": "res://assets/nx8/teams/club29.webp",
	"club30": "res://assets/nx8/teams/club30.webp",
	"club31": "res://assets/nx8/teams/club31.webp",
	"club32": "res://assets/nx8/teams/club32.webp",
	"club33": "res://assets/nx8/teams/club33.webp",
	"club34": "res://assets/nx8/teams/club34.webp",
	"club35": "res://assets/nx8/teams/club35.webp",
	"club36": "res://assets/nx8/teams/club36.webp",
	"club37": "res://assets/nx8/teams/club37.webp",
	"club38": "res://assets/nx8/teams/club38.webp",
	"club39": "res://assets/nx8/teams/club39.webp",
	"club40": "res://assets/nx8/teams/club40.webp",
	"club41": "res://assets/nx8/teams/club41.webp",
	"club42": "res://assets/nx8/teams/club42.webp",
	"club43": "res://assets/nx8/teams/club43.webp",
	"club44": "res://assets/nx8/teams/club44.webp",
	"club45": "res://assets/nx8/teams/club45.webp",
	"club46": "res://assets/nx8/teams/club46.webp",
	"club47": "res://assets/nx8/teams/club47.webp",
	"club48": "res://assets/nx8/teams/club48.webp",
	"club49": "res://assets/nx8/teams/club49.webp",
	"club50": "res://assets/nx8/teams/club50.webp",
	"club51": "res://assets/nx8/teams/club51.webp",
	"club52": "res://assets/nx8/teams/club52.webp",
	"club53": "res://assets/nx8/teams/club53.webp",
	"club54": "res://assets/nx8/teams/club54.webp",
	"club55": "res://assets/nx8/teams/club55.webp",
	"club56": "res://assets/nx8/teams/club56.webp",
	"club57": "res://assets/nx8/teams/club57.webp",
	"club58": "res://assets/nx8/teams/club58.webp",
	"club59": "res://assets/nx8/teams/club59.webp",
	"club60": "res://assets/nx8/teams/club60.webp",
	"club61": "res://assets/nx8/teams/club61.webp",
	"club62": "res://assets/nx8/teams/club62.webp",
	"club63": "res://assets/nx8/teams/club63.webp",
	"nat00": "res://assets/nx8/teams/nat00.webp",
	"nat01": "res://assets/nx8/teams/nat01.webp",
	"nat02": "res://assets/nx8/teams/nat02.webp",
	"nat03": "res://assets/nx8/teams/nat03.webp",
	"nat04": "res://assets/nx8/teams/nat04.webp",
	"nat05": "res://assets/nx8/teams/nat05.webp",
	"nat06": "res://assets/nx8/teams/nat06.webp",
	"nat07": "res://assets/nx8/teams/nat07.webp",
	"nat08": "res://assets/nx8/teams/nat08.webp",
	"nat09": "res://assets/nx8/teams/nat09.webp",
	"nat10": "res://assets/nx8/teams/nat10.webp",
	"nat11": "res://assets/nx8/teams/nat11.webp",
	"nat12": "res://assets/nx8/teams/nat12.webp",
	"nat13": "res://assets/nx8/teams/nat13.webp",
	"nat14": "res://assets/nx8/teams/nat14.webp",
	"nat15": "res://assets/nx8/teams/nat15.webp",
	"nat16": "res://assets/nx8/teams/nat16.webp",
	"nat17": "res://assets/nx8/teams/nat17.webp",
	"nat18": "res://assets/nx8/teams/nat18.webp",
	"nat19": "res://assets/nx8/teams/nat19.webp",
	"nat20": "res://assets/nx8/teams/nat20.webp",
	"nat21": "res://assets/nx8/teams/nat21.webp",
	"nat22": "res://assets/nx8/teams/nat22.webp",
	"nat23": "res://assets/nx8/teams/nat23.webp",
	"nat24": "res://assets/nx8/teams/nat24.webp",
	"nat25": "res://assets/nx8/teams/nat25.webp",
	"nat26": "res://assets/nx8/teams/nat26.webp",
	"nat27": "res://assets/nx8/teams/nat27.webp",
	"nat28": "res://assets/nx8/teams/nat28.webp",
	"nat29": "res://assets/nx8/teams/nat29.webp",
	"nat30": "res://assets/nx8/teams/nat30.webp",
	"nat31": "res://assets/nx8/teams/nat31.webp",
	"nat32": "res://assets/nx8/teams/nat32.webp",
	"nat33": "res://assets/nx8/teams/nat33.webp",
	"nat34": "res://assets/nx8/teams/nat34.webp",
	"nat35": "res://assets/nx8/teams/nat35.webp",
	"nat36": "res://assets/nx8/teams/nat36.webp",
	"nat37": "res://assets/nx8/teams/nat37.webp",
	"nat38": "res://assets/nx8/teams/nat38.webp",
	"nat39": "res://assets/nx8/teams/nat39.webp",
	"nat40": "res://assets/nx8/teams/nat40.webp",
	"nat41": "res://assets/nx8/teams/nat41.webp",
	"nat42": "res://assets/nx8/teams/nat42.webp",
	"nat43": "res://assets/nx8/teams/nat43.webp",
	"nat44": "res://assets/nx8/teams/nat44.webp",
	"nat45": "res://assets/nx8/teams/nat45.webp",
	"nat46": "res://assets/nx8/teams/nat46.webp",
	"nat47": "res://assets/nx8/teams/nat47.webp",
	"nat48": "res://assets/nx8/teams/nat48.webp",
	"nat49": "res://assets/nx8/teams/nat49.webp",
	"nat50": "res://assets/nx8/teams/nat50.webp",
	"nat51": "res://assets/nx8/teams/nat51.webp",
	"nat52": "res://assets/nx8/teams/nat52.webp",
	"nat53": "res://assets/nx8/teams/nat53.webp",
	"nat54": "res://assets/nx8/teams/nat54.webp",
	"nat55": "res://assets/nx8/teams/nat55.webp",
	"nat56": "res://assets/nx8/teams/nat56.webp",
	"nat57": "res://assets/nx8/teams/nat57.webp",
	"nat58": "res://assets/nx8/teams/nat58.webp",
	"nat59": "res://assets/nx8/teams/nat59.webp",
	"spt00": "res://assets/nx8/teams/spt00.webp",
	"spt01": "res://assets/nx8/teams/spt01.webp",
	"spt02": "res://assets/nx8/teams/spt02.webp",
	"spt03": "res://assets/nx8/teams/spt03.webp",
	"spt04": "res://assets/nx8/teams/spt04.webp",
	"spt05": "res://assets/nx8/teams/spt05.webp",
	"spt06": "res://assets/nx8/teams/spt06.webp",
	"spt07": "res://assets/nx8/teams/spt07.webp",
	"spt08": "res://assets/nx8/teams/spt08.webp",
	"spt09": "res://assets/nx8/teams/spt09.webp",
	"spt10": "res://assets/nx8/teams/spt10.webp",
	"spt11": "res://assets/nx8/teams/spt11.webp",
	"spt12": "res://assets/nx8/teams/spt12.webp",
	"spt13": "res://assets/nx8/teams/spt13.webp",
	"spt14": "res://assets/nx8/teams/spt14.webp",
	"spt15": "res://assets/nx8/teams/spt15.webp",
	"spt16": "res://assets/nx8/teams/spt16.webp",
	"spt17": "res://assets/nx8/teams/spt17.webp",
	"spt18": "res://assets/nx8/teams/spt18.webp",
	"spt19": "res://assets/nx8/teams/spt19.webp",
	"gal00": "res://assets/nx8/teams/gal00.webp",
	"gal01": "res://assets/nx8/teams/gal01.webp",
	"gal02": "res://assets/nx8/teams/gal02.webp",
	"gal03": "res://assets/nx8/teams/gal03.webp",
	"gal04": "res://assets/nx8/teams/gal04.webp",
	"gal05": "res://assets/nx8/teams/gal05.webp",
	"gal06": "res://assets/nx8/teams/gal06.webp",
	"gal07": "res://assets/nx8/teams/gal07.webp",
	"gal08": "res://assets/nx8/teams/gal08.webp",
	"gal09": "res://assets/nx8/teams/gal09.webp",
	"gal10": "res://assets/nx8/teams/gal10.webp",
	"gal11": "res://assets/nx8/teams/gal11.webp",
	"gal12": "res://assets/nx8/teams/gal12.webp",
	"gal13": "res://assets/nx8/teams/gal13.webp",
	"gal14": "res://assets/nx8/teams/gal14.webp",
	"gal15": "res://assets/nx8/teams/gal15.webp",
	"gal16": "res://assets/nx8/teams/gal16.webp",
	"gal17": "res://assets/nx8/teams/gal17.webp",
	"gal18": "res://assets/nx8/teams/gal18.webp",
	"gal19": "res://assets/nx8/teams/gal19.webp",
	"vip00": "res://assets/g/teams/vip00.webp",
	"vip01": "res://assets/g/teams/vip01.webp",
	"vip02": "res://assets/g/teams/vip02.webp",
	"vip03": "res://assets/g/teams/vip03.webp",
	"vip04": "res://assets/g/teams/vip04.webp",
	"vip05": "res://assets/g/teams/vip05.webp",
	"vip06": "res://assets/g/teams/vip06.webp",
	"vip07": "res://assets/g/teams/vip07.webp",
	"vip08": "res://assets/g/teams/vip08.webp",
	"vip09": "res://assets/g/teams/vip09.webp",
	"vip10": "res://assets/g/teams/vip10.webp",
	"vip11": "res://assets/g/teams/vip11.webp",
	"car00": "res://assets/g/teams/car00.webp",
	"car01": "res://assets/g/teams/car01.webp",
	"car02": "res://assets/g/teams/car02.webp",
	"car03": "res://assets/g/teams/car03.webp",
	"car04": "res://assets/g/teams/car04.webp",
	"car05": "res://assets/g/teams/car05.webp",
	"car06": "res://assets/g/teams/car06.webp",
	"car07": "res://assets/g/teams/car07.webp",
	"car08": "res://assets/g/teams/car08.webp",
	"car09": "res://assets/g/teams/car09.webp",
	"car10": "res://assets/g/teams/car10.webp",
	"car11": "res://assets/g/teams/car11.webp",
	"car12": "res://assets/g/teams/car12.webp",
	"car13": "res://assets/g/teams/car13.webp",
	"elite00": "res://assets/g/teams/elite00.webp",
	"elite01": "res://assets/g/teams/elite01.webp",
	"elite02": "res://assets/g/teams/elite02.webp",
	"elite03": "res://assets/g/teams/elite03.webp",
	"elite04": "res://assets/g/teams/elite04.webp",
	"elite05": "res://assets/g/teams/elite05.webp",
	"elite06": "res://assets/g/teams/elite06.webp",
	"elite07": "res://assets/g/teams/elite07.webp",
	"elite08": "res://assets/g/teams/elite08.webp",
	"elite09": "res://assets/g/teams/elite09.webp",
	"elite10": "res://assets/g/teams/elite10.webp",
	"elite11": "res://assets/g/teams/elite11.webp",
	"elite12": "res://assets/g/teams/elite12.webp",
	"elite13": "res://assets/g/teams/elite13.webp",
	"elite14": "res://assets/g/teams/elite14.webp",
	"elite15": "res://assets/g/teams/elite15.webp",
	"elite16": "res://assets/g/teams/elite16.webp",
	"elite17": "res://assets/g/teams/elite17.webp",
	"elite18": "res://assets/g/teams/elite18.webp",
	"elite19": "res://assets/g/teams/elite19.webp",
	"elite20": "res://assets/g/teams/elite20.webp",
	"elite21": "res://assets/g/teams/elite21.webp",
	"elite22": "res://assets/g/teams/elite22.webp",
	"elite23": "res://assets/g/teams/elite23.webp",
	"elite24": "res://assets/g/teams/elite24.webp",
	"elite25": "res://assets/g/teams/elite25.webp",
	"elite26": "res://assets/g/teams/elite26.webp",
	"elite27": "res://assets/g/teams/elite27.webp",
	"elite28": "res://assets/g/teams/elite28.webp",
	"elite29": "res://assets/g/teams/elite29.webp",
	"elite30": "res://assets/g/teams/elite30.webp",
	"elite31": "res://assets/g/teams/elite31.webp",
	"elite32": "res://assets/g/teams/elite32.webp",
	"elite33": "res://assets/g/teams/elite33.webp",
	"elite34": "res://assets/g/teams/elite34.webp",
	"elite35": "res://assets/g/teams/elite35.webp",
	"emb00": "res://assets/g/teams/emb00.webp",
	"emb01": "res://assets/g/teams/emb01.webp",
	"emb02": "res://assets/g/teams/emb02.webp",
	"emb03": "res://assets/g/teams/emb03.webp",
	"emb04": "res://assets/g/teams/emb04.webp",
	"emb05": "res://assets/g/teams/emb05.webp",
	"emb06": "res://assets/g/teams/emb06.webp",
	"emb07": "res://assets/g/teams/emb07.webp",
	"emb08": "res://assets/g/teams/emb08.webp",
	"emb09": "res://assets/g/teams/emb09.webp",
	"emb10": "res://assets/g/teams/emb10.webp",
	"emb11": "res://assets/g/teams/emb11.webp",
	"emb12": "res://assets/g/teams/emb12.webp",
	"emb13": "res://assets/g/teams/emb13.webp",
	"emb14": "res://assets/g/teams/emb14.webp",
	"emb15": "res://assets/g/teams/emb15.webp",
	"leg00": "res://assets/g/teams/leg00.webp",
	"leg01": "res://assets/g/teams/leg01.webp",
	"leg02": "res://assets/g/teams/leg02.webp",
	"leg03": "res://assets/g/teams/leg03.webp",
	"leg04": "res://assets/g/teams/leg04.webp",
	"leg05": "res://assets/g/teams/leg05.webp",
	"chrome00": "res://assets/g/teams/chrome00.webp",
	"chrome01": "res://assets/g/teams/chrome01.webp",
	"chrome02": "res://assets/g/teams/chrome02.webp",
	"chrome03": "res://assets/g/teams/chrome03.webp",
	"chrome04": "res://assets/g/teams/chrome04.webp",
	"chrome05": "res://assets/g/teams/chrome05.webp",
	"chrome06": "res://assets/g/teams/chrome06.webp",
	"chrome07": "res://assets/g/teams/chrome07.webp",
}
## balls 0-12 = the NX8 balls (b<i>.png sphere textures, s<i>.webp card thumbnails); 13-35 keep the v4 art.
const BALL_IMG := {
	"b0": "res://assets/nx8/balls/b0.png",
	"b1": "res://assets/nx8/balls/b1.png",
	"b2": "res://assets/nx8/balls/b2.png",
	"b3": "res://assets/nx8/balls/b3.png",
	"b4": "res://assets/nx8/balls/b4.png",
	"b5": "res://assets/nx8/balls/b5.png",
	"b6": "res://assets/nx8/balls/b6.png",
	"b7": "res://assets/nx8/balls/b7.png",
	"b8": "res://assets/nx8/balls/b8.png",
	"b9": "res://assets/nx8/balls/b9.png",
	"b10": "res://assets/nx8/balls/b10.png",
	"b11": "res://assets/nx8/balls/b11.png",
	"b12": "res://assets/nx8/balls/b12.png",
	"b13": "res://assets/g/balls/b13.webp",
	"b14": "res://assets/g/balls/b14.webp",
	"b15": "res://assets/g/balls/b15.webp",
	"b16": "res://assets/g/balls/b16.webp",
	"b17": "res://assets/g/balls/b17.webp",
	"b18": "res://assets/g/balls/b18.webp",
	"b19": "res://assets/g/balls/b19.webp",
	"b20": "res://assets/g/balls/b20.webp",
	"b21": "res://assets/g/balls/b21.webp",
	"b22": "res://assets/g/balls/b22.webp",
	"b23": "res://assets/g/balls/b23.webp",
	"b24": "res://assets/g/balls/b24.webp",
	"b25": "res://assets/g/balls/b25.webp",
	"b26": "res://assets/g/balls/b26.webp",
	"b27": "res://assets/g/balls/b27.webp",
	"b28": "res://assets/g/balls/b28.webp",
	"b29": "res://assets/g/balls/b29.webp",
	"b30": "res://assets/g/balls/b30.webp",
	"b31": "res://assets/g/balls/b31.webp",
	"b32": "res://assets/g/balls/b32.webp",
	"b33": "res://assets/g/balls/b33.webp",
	"b34": "res://assets/g/balls/b34.webp",
	"b35": "res://assets/g/balls/b35.webp",
}
const BALL_THUMB := {
	"b0": "res://assets/nx8/balls/s0.webp",
	"b1": "res://assets/nx8/balls/s1.webp",
	"b2": "res://assets/nx8/balls/s2.webp",
	"b3": "res://assets/nx8/balls/s3.webp",
	"b4": "res://assets/nx8/balls/s4.webp",
	"b5": "res://assets/nx8/balls/s5.webp",
	"b6": "res://assets/nx8/balls/s6.webp",
	"b7": "res://assets/nx8/balls/s7.webp",
	"b8": "res://assets/nx8/balls/s8.webp",
	"b9": "res://assets/nx8/balls/s9.webp",
	"b10": "res://assets/nx8/balls/s10.webp",
	"b11": "res://assets/nx8/balls/s11.webp",
	"b12": "res://assets/nx8/balls/s12.webp",
}
const FIELD_IMG := {
	"pitch": "res://assets/g/fields/pitch.webp",
	"acmilan": "res://assets/g/fields/acmilan.webp",
	"aqua": "res://assets/g/fields/aqua.webp",
	"arena": "res://assets/g/fields/arena.webp",
	"arena2": "res://assets/g/fields/arena2.webp",
	"asphalt": "res://assets/g/fields/asphalt.webp",
	"barcelona": "res://assets/g/fields/barcelona.webp",
	"checker": "res://assets/g/fields/checker.webp",
	"classic": "res://assets/g/fields/classic.webp",
	"court": "res://assets/g/fields/court.webp",
	"cyberbox": "res://assets/g/fields/cyberbox.webp",
	"desert": "res://assets/g/fields/desert.webp",
	"esteghlal": "res://assets/g/fields/esteghlal.webp",
	"forest": "res://assets/g/fields/forest.webp",
	"futsal": "res://assets/g/fields/futsal.webp",
	"grove": "res://assets/g/fields/grove.webp",
	"ice": "res://assets/g/fields/ice.webp",
	"lava": "res://assets/g/fields/lava.webp",
	"leather": "res://assets/g/fields/leather.webp",
	"mahogany": "res://assets/g/fields/mahogany.webp",
	"mancity": "res://assets/g/fields/mancity.webp",
	"neon": "res://assets/g/fields/neon.webp",
	"ocean": "res://assets/g/fields/ocean.webp",
	"persepolis": "res://assets/g/fields/persepolis.webp",
	"pool": "res://assets/g/fields/pool.webp",
	"psg": "res://assets/g/fields/psg.webp",
	"realmadrid": "res://assets/g/fields/realmadrid.webp",
	"royal": "res://assets/g/fields/royal.webp",
	"stadium": "res://assets/g/fields/stadium.webp",
	"street": "res://assets/g/fields/street.webp",
	"streetarena": "res://assets/g/fields/streetarena.webp",
}
const FIELD_THUMB := {
	"pitch": "res://assets/g/fthumb/pitch.webp",
	"acmilan": "res://assets/g/fthumb/acmilan.webp",
	"aqua": "res://assets/g/fthumb/aqua.webp",
	"arena": "res://assets/g/fthumb/arena.webp",
	"arena2": "res://assets/g/fthumb/arena2.webp",
	"asphalt": "res://assets/g/fthumb/asphalt.webp",
	"barcelona": "res://assets/g/fthumb/barcelona.webp",
	"checker": "res://assets/g/fthumb/checker.webp",
	"classic": "res://assets/g/fthumb/classic.webp",
	"court": "res://assets/g/fthumb/court.webp",
	"cyberbox": "res://assets/g/fthumb/cyberbox.webp",
	"desert": "res://assets/g/fthumb/desert.webp",
	"esteghlal": "res://assets/g/fthumb/esteghlal.webp",
	"forest": "res://assets/g/fthumb/forest.webp",
	"futsal": "res://assets/g/fthumb/futsal.webp",
	"grove": "res://assets/g/fthumb/grove.webp",
	"ice": "res://assets/g/fthumb/ice.webp",
	"lava": "res://assets/g/fthumb/lava.webp",
	"leather": "res://assets/g/fthumb/leather.webp",
	"mahogany": "res://assets/g/fthumb/mahogany.webp",
	"mancity": "res://assets/g/fthumb/mancity.webp",
	"neon": "res://assets/g/fthumb/neon.webp",
	"ocean": "res://assets/g/fthumb/ocean.webp",
	"persepolis": "res://assets/g/fthumb/persepolis.webp",
	"pool": "res://assets/g/fthumb/pool.webp",
	"psg": "res://assets/g/fthumb/psg.webp",
	"realmadrid": "res://assets/g/fthumb/realmadrid.webp",
	"royal": "res://assets/g/fthumb/royal.webp",
	"stadium": "res://assets/g/fthumb/stadium.webp",
	"street": "res://assets/g/fthumb/street.webp",
	"streetarena": "res://assets/g/fthumb/streetarena.webp",
}
const GOAL_IMG := {
	"black": "res://assets/g/goals/black.webp",
	"blue": "res://assets/g/goals/blue.webp",
	"gold": "res://assets/g/goals/gold.webp",
	"ice": "res://assets/g/goals/ice.webp",
	"red": "res://assets/g/goals/red.webp",
	"rope": "res://assets/g/goals/rope.webp",
	"white": "res://assets/g/goals/white.webp",
	"wood": "res://assets/g/goals/wood.webp",
}
const UI := {
	"neb_base": "res://assets/g/ui/neb_base.jpg",
	"neb_win": "res://assets/g/ui/neb_win.jpg",
	"neb_lose": "res://assets/g/ui/neb_lose.jpg",
	"neb_system": "res://assets/g/ui/neb_system.jpg",
	"stars1": "res://assets/g/ui/stars1.png",
	"stars2": "res://assets/g/ui/stars2.png",
	"planet": "res://assets/g/ui/planet.webp",
	"scan": "res://assets/g/ui/scan.png",
	"portal_friends": "res://assets/g/ui/portal_friends.webp",
	"disc_3d": "res://assets/g/ui/disc_3d.webp",
	"b_gift": "res://assets/g/ui/b_gift.webp",
	"b_star": "res://assets/g/ui/b_star.webp",
	"b_trophy": "res://assets/g/ui/b_trophy.webp",
	"ball": "res://assets/g/ui/ball.webp",
	"ballcrown": "res://assets/g/ui/ballcrown.webp",
	"chest": "res://assets/g/ui/chest.webp",
	"coin": "res://assets/g/ui/coin.webp",
	"coinpotion": "res://assets/g/ui/coinpotion.webp",
	"crown": "res://assets/g/ui/crown.webp",
	"crystal": "res://assets/g/ui/crystal.webp",
	"cup": "res://assets/g/ui/cup.webp",
	"defeat": "res://assets/g/ui/defeat.webp",
	"disc_top": "res://assets/g/ui/disc_top.webp",
	"draw": "res://assets/g/ui/draw.webp",
	"emb_core": "res://assets/g/ui/emb_core.webp",
	"emb_crown": "res://assets/g/ui/emb_crown.webp",
	"emb_gem": "res://assets/g/ui/emb_gem.webp",
	"emb_rank": "res://assets/g/ui/emb_rank.webp",
	"emb_shield": "res://assets/g/ui/emb_shield.webp",
	"emb_wings": "res://assets/g/ui/emb_wings.webp",
	"gate": "res://assets/g/ui/gate.webp",
	"gem": "res://assets/g/ui/gem.webp",
	"goaltxt": "res://assets/g/ui/goaltxt.webp",
	"holoA": "res://assets/g/ui/holoA.webp",
	"holoB": "res://assets/g/ui/holoB.webp",
	"holopad": "res://assets/g/ui/holopad.webp",
	"holotrophy": "res://assets/g/ui/holotrophy.webp",
	"i_cart": "res://assets/g/ui/i_cart.webp",
	"i_gear": "res://assets/g/ui/i_gear.webp",
	"i_gift": "res://assets/g/ui/i_gift.webp",
	"i_home": "res://assets/g/ui/i_home.webp",
	"i_trophy": "res://assets/g/ui/i_trophy.webp",
	"logo_nexora": "res://assets/g/ui/logo_nexora.webp",
	"medal_bronze": "res://assets/g/ui/medal_bronze.webp",
	"medal_epic": "res://assets/g/ui/medal_epic.webp",
	"medal_gold": "res://assets/g/ui/medal_gold.webp",
	"medal_silver": "res://assets/g/ui/medal_silver.webp",
	"nx_logo": "res://assets/g/ui/nx_logo.webp",
	"orb": "res://assets/g/ui/orb.webp",
	"pedestal": "res://assets/g/ui/pedestal.webp",
	"portal_brain": "res://assets/g/ui/portal_brain.webp",
	"portal_galaxy": "res://assets/g/ui/portal_galaxy.webp",
	"portal_gamepad": "res://assets/g/ui/portal_gamepad.webp",
	"portal_globe": "res://assets/g/ui/portal_globe.webp",
	"portal_profile": "res://assets/g/ui/portal_profile.webp",
	"portal_shop": "res://assets/g/ui/portal_shop.webp",
	"r_back": "res://assets/g/ui/r_back.webp",
	"r_gear": "res://assets/g/ui/r_gear.webp",
	"r_play": "res://assets/g/ui/r_play.webp",
	"r_plus": "res://assets/g/ui/r_plus.webp",
	"r_star": "res://assets/g/ui/r_star.webp",
	"radar": "res://assets/g/ui/radar.webp",
	"ring": "res://assets/g/ui/ring.webp",
	"ring_0": "res://assets/g/ui/ring_0.webp",
	"ring_1": "res://assets/g/ui/ring_1.webp",
	"ring_2": "res://assets/g/ui/ring_2.webp",
	"ring_3": "res://assets/g/ui/ring_3.webp",
	"scene_arena": "res://assets/g/ui/scene_arena.webp",
	"scene_fire": "res://assets/g/ui/scene_fire.webp",
	"scene_forest": "res://assets/g/ui/scene_forest.webp",
	"scene_holo": "res://assets/g/ui/scene_holo.webp",
	"scene_ice": "res://assets/g/ui/scene_ice.webp",
	"shield_crown": "res://assets/g/ui/shield_crown.webp",
	"shield_epic": "res://assets/g/ui/shield_epic.webp",
	"shield_star": "res://assets/g/ui/shield_star.webp",
	"station": "res://assets/g/ui/station.webp",
	"ticket": "res://assets/g/ui/ticket.webp",
	"victory": "res://assets/g/ui/victory.webp",
	"vs": "res://assets/g/ui/vs.webp",
	"xp": "res://assets/g/ui/xp.webp",
}
const SFX := {
	"BallHit-01": "res://assets/sfx/BallHit-01.mp3",
	"ballHitsThePost": "res://assets/sfx/ballHitsThePost.mp3",
	"crowd-03": "res://assets/sfx/crowd-03.mp3",
	"gameIsFinishedWistle": "res://assets/sfx/gameIsFinishedWistle.mp3",
	"goal": "res://assets/sfx/goal.wav",
	"goalHappened-01": "res://assets/sfx/goalHappened-01.mp3",
	"hit_ball": "res://assets/sfx/hit_ball.wav",
	"hit_piece": "res://assets/sfx/hit_piece.mp3",
	"music": "res://assets/g/sfx/music.mp3",
	"select": "res://assets/g/sfx/select.wav",
	"startWistle": "res://assets/sfx/startWistle.mp3",
	"nx_ready": "res://assets/g/sfx/nx_ready.mp3",
	"nx_chat": "res://assets/g/sfx/nx_chat.mp3",
	"nx_join": "res://assets/g/sfx/nx_join.mp3",
	"nx_leave": "res://assets/g/sfx/nx_leave.mp3",
	"nx_win": "res://assets/g/sfx/nx_win.mp3",
	"nx_lose": "res://assets/g/sfx/nx_lose.mp3",
	"nx_tick": "res://assets/g/sfx/nx_tick.mp3",
}
const UI2 := {
	"btn_back": "res://assets/g/ui2/btn_back.webp",
	"btn_chest": "res://assets/g/ui2/btn_chest.webp",
	"btn_cup": "res://assets/g/ui2/btn_cup.webp",
	"btn_daily": "res://assets/g/ui2/btn_daily.webp",
	"btn_friends": "res://assets/g/ui2/btn_friends.webp",
	"btn_play": "res://assets/g/ui2/btn_play.webp",
	"btn_settings": "res://assets/g/ui2/btn_settings.webp",
	"btn_shop": "res://assets/g/ui2/btn_shop.webp",
	"btn_team": "res://assets/g/ui2/btn_team.webp",
	"c_ball": "res://assets/g/ui2/c_ball.webp",
	"c_bell": "res://assets/g/ui2/c_bell.webp",
	"c_calendar": "res://assets/g/ui2/c_calendar.webp",
	"c_chest": "res://assets/g/ui2/c_chest.webp",
	"c_coin": "res://assets/g/ui2/c_coin.webp",
	"c_gear": "res://assets/g/ui2/c_gear.webp",
	"c_gem": "res://assets/g/ui2/c_gem.webp",
	"c_gift": "res://assets/g/ui2/c_gift.webp",
	"c_mega": "res://assets/g/ui2/c_mega.webp",
	"c_profile": "res://assets/g/ui2/c_profile.webp",
	"c_shield": "res://assets/g/ui2/c_shield.webp",
	"c_stadium": "res://assets/g/ui2/c_stadium.webp",
	"c_star": "res://assets/g/ui2/c_star.webp",
	"c_tactics": "res://assets/g/ui2/c_tactics.webp",
	"c_team": "res://assets/g/ui2/c_team.webp",
	"c_trophy": "res://assets/g/ui2/c_trophy.webp",
	"console": "res://assets/g/ui2/console.webp",
	"crystal": "res://assets/g/ui2/crystal.webp",
	"d_arch": "res://assets/g/ui2/d_arch.webp",
	"d_banner": "res://assets/g/ui2/d_banner.webp",
	"d_crystal": "res://assets/g/ui2/d_crystal.webp",
	"d_orbstand": "res://assets/g/ui2/d_orbstand.webp",
	"d_plant": "res://assets/g/ui2/d_plant.webp",
	"d_sat": "res://assets/g/ui2/d_sat.webp",
	"frame_wide": "res://assets/g/ui2/frame_wide.webp",
	"globe": "res://assets/g/ui2/globe.webp",
	"hero": "res://assets/g/ui2/hero.webp",
	"home_bg": "res://assets/g/ui2/home_bg.jpg",
	"mascot": "res://assets/g/ui2/mascot.webp",
	"mascot2": "res://assets/g/ui2/mascot2.webp",
	"mascot3": "res://assets/g/ui2/mascot3.webp",
	"orb": "res://assets/g/ui2/orb.webp",
	"portal": "res://assets/g/ui2/portal.webp",
	"ring": "res://assets/g/ui2/ring.webp",
	"screens": "res://assets/g/ui2/screens.webp",
	"x_ball": "res://assets/g/ui2/x_ball.webp",
	"x_bell": "res://assets/g/ui2/x_bell.webp",
	"x_chest": "res://assets/g/ui2/x_chest.webp",
	"x_coins": "res://assets/g/ui2/x_coins.webp",
	"x_crown": "res://assets/g/ui2/x_crown.webp",
	"x_gear": "res://assets/g/ui2/x_gear.webp",
	"x_gem": "res://assets/g/ui2/x_gem.webp",
	"x_gift": "res://assets/g/ui2/x_gift.webp",
	"x_home": "res://assets/g/ui2/x_home.webp",
	"x_medal": "res://assets/g/ui2/x_medal.webp",
	"x_player": "res://assets/g/ui2/x_player.webp",
	"x_shield": "res://assets/g/ui2/x_shield.webp",
	"x_star": "res://assets/g/ui2/x_star.webp",
	"x_statue": "res://assets/g/ui2/x_statue.webp",
	"x_tactics": "res://assets/g/ui2/x_tactics.webp",
	"x_team": "res://assets/g/ui2/x_team.webp",
	"x_trophy": "res://assets/g/ui2/x_trophy.webp",
}
const ORACLE := {
	"hero": "res://assets/g/oracle/oracle_hero.webp",
	"idle": "res://assets/g/oracle/oracle_idle.webp",
	"hello": "res://assets/g/oracle/oracle_hello.webp",
	"wave": "res://assets/g/oracle/oracle_wave.webp",
	"content": "res://assets/g/oracle/oracle_content.webp",
	"joy": "res://assets/g/oracle/oracle_joy.webp",
	"laugh": "res://assets/g/oracle/oracle_laugh.webp",
	"happy": "res://assets/g/oracle/oracle_happy.webp",
	"excited": "res://assets/g/oracle/oracle_excited.webp",
	"spin": "res://assets/g/oracle/oracle_spin.webp",
	"present": "res://assets/g/oracle/oracle_present.webp",
	"idea": "res://assets/g/oracle/oracle_idea.webp",
	"focus": "res://assets/g/oracle/oracle_focus.webp",
	"curious": "res://assets/g/oracle/oracle_curious.webp",
	"confused": "res://assets/g/oracle/oracle_confused.webp",
	"alert": "res://assets/g/oracle/oracle_alert.webp",
	"calm": "res://assets/g/oracle/oracle_calm.webp",
	"neutral": "res://assets/g/oracle/oracle_neutral.webp",
	"sleep": "res://assets/g/oracle/oracle_sleep.webp",
}
const ARROW_IMG := {
	"head_e": "res://assets/g/arrow/head_e.webp",
	"head_s": "res://assets/g/arrow/head_s.webp",
	"shaft_e": "res://assets/g/arrow/shaft_e.webp",
	"shaft_s": "res://assets/g/arrow/shaft_s.webp",
}
const MENU := {
	"ic_settings": "res://assets/g/menu/ic_settings.webp",
	"ic_home": "res://assets/g/menu/ic_home.webp",
	"ic_trophy": "res://assets/g/menu/ic_trophy.webp",
	"ic_shop": "res://assets/g/menu/ic_shop.webp",
	"ic_gift": "res://assets/g/menu/ic_gift.webp",
	"ic_play": "res://assets/g/menu/ic_play.webp",
	"ic_pause": "res://assets/g/menu/ic_pause.webp",
	"ic_music": "res://assets/g/menu/ic_music.webp",
	"ic_sound": "res://assets/g/menu/ic_sound.webp",
	"ic_mute": "res://assets/g/menu/ic_mute.webp",
	"ic_info": "res://assets/g/menu/ic_info.webp",
	"ic_help": "res://assets/g/menu/ic_help.webp",
	"ic_exit": "res://assets/g/menu/ic_exit.webp",
	"ic_mail": "res://assets/g/menu/ic_mail.webp",
	"ic_bell": "res://assets/g/menu/ic_bell.webp",
	"ic_friends": "res://assets/g/menu/ic_friends.webp",
	"ic_plus": "res://assets/g/menu/ic_plus.webp",
	"g_coin": "res://assets/g/menu/g_coin.webp",
	"g_gem": "res://assets/g/menu/g_gem.webp",
	"g_xp": "res://assets/g/menu/g_xp.webp",
	"g_crown": "res://assets/g/menu/g_crown.webp",
	"g_star": "res://assets/g/menu/g_star.webp",
	"g_check": "res://assets/g/menu/g_check.webp",
	"g_x": "res://assets/g/menu/g_x.webp",
	"g_plus": "res://assets/g/menu/g_plus.webp",
	"g_mail": "res://assets/g/menu/g_mail.webp",
	"g_friends": "res://assets/g/menu/g_friends.webp",
	"g_addfriend": "res://assets/g/menu/g_addfriend.webp",
	"g_block": "res://assets/g/menu/g_block.webp",
	"g_chevrons": "res://assets/g/menu/g_chevrons.webp",
	"g_ticket": "res://assets/g/menu/g_ticket.webp",
	"g_ticket_gold": "res://assets/g/menu/g_ticket_gold.webp",
	"g_signal": "res://assets/g/menu/g_signal.webp",
	"rank_bronze": "res://assets/g/menu/rank_bronze.webp",
	"rank_silver": "res://assets/g/menu/rank_silver.webp",
	"rank_gold": "res://assets/g/menu/rank_gold.webp",
	"rank_epic": "res://assets/g/menu/rank_epic.webp",
	"shield_crown": "res://assets/g/menu/shield_crown.webp",
	"shield_star": "res://assets/g/menu/shield_star.webp",
	"shield_gem": "res://assets/g/menu/shield_gem.webp",
	"logo": "res://assets/g/menu/logo.webp",
	"title_banner": "res://assets/g/menu/title_banner.webp",
	"vs_card": "res://assets/g/menu/vs_card.webp",
	"banner_victory": "res://assets/g/menu/banner_victory.webp",
	"banner_defeat": "res://assets/g/menu/banner_defeat.webp",
	"banner_draw": "res://assets/g/menu/banner_draw.webp",
	"banner_goal": "res://assets/g/menu/banner_goal.webp",
	"frame_panel": "res://assets/g/menu/frame_panel.webp",
	"frame_wide": "res://assets/g/menu/frame_wide.webp",
	"frame_small": "res://assets/g/menu/frame_small.webp",
	"pedestal": "res://assets/g/menu/pedestal.webp",
	"holo_ring": "res://assets/g/menu/holo_ring.webp",
	"glow_orb": "res://assets/g/menu/glow_orb.webp",
	"ring": "res://assets/g/menu/ring.webp",
	"sparkle": "res://assets/g/menu/sparkle.webp",
	"bg_stadium": "res://assets/g/menu/bg_stadium.webp",
	"bg_holo": "res://assets/g/menu/bg_holo.webp",
}
