echo "BEGIN;"

cat ./mtg-rulings.json ./mtg-data.json | jq --raw-output --slurp '

#Reused functions
def boolflags(prop; $names):
. as $obj |
    names | map({
        key: "\( $obj | path(prop) | join("_") )_has_\(. | ascii_downcase)",
        value: (. as $name | $obj | prop | index($name) != null)
    })
| from_entries
;

def tosql:
if type == "number" then tostring
elif . == true then "TRUE"
elif . == false then "FALSE"
elif type == "string" then ([39]|implode) as $apos |
    $apos
        + (@json | .[1:-1] | gsub($apos; $apos + $apos))
    + $apos
elif type == "null" then "null"
else error("tried to SQL a compound value!") end
;

#Take each input file out of the array
.[0] as $rulings | .[1] as $cards | (


# Read all cards in the cards table
($cards | .[]
| del(.keywords) # Remove the properties which are implemented as foreign keys
| . #Flatten certain small array properties into multiple boolean columns
    + boolflags(.color_identity; ["B", "G", "R", "U", "W"])
    + boolflags(.colors; ["B", "G", "R", "U", "W"])
    + boolflags(.games; ["arena", "astral", "mtgo", "paper", "sega"])
| del(.color_identity) | del(.colors) | del(.games) #Remove those same small array properties
| . + { released_at: (.released_at / 1000) | todateiso8601 } # Put date property into ISO8601
| to_entries
| "INSERT INTO cards ( \( map(.key) | join(",") ) ) VALUES ( \( map(.value | tosql) | join(",") ) );"
),

# read the keywords of each card into the keywords table
($cards | .[]
| .oracle_id as $card_id
| .keywords | .[]
| "INSERT INTO keywords (card_id, keyword_text) VALUES ( \($card_id | tosql), \(tosql) );"),

# Read the rulings file into the rulings table
($rulings | .[] |
"INSERT INTO rulings (card_id, published_at, ruling_text)"
+ " VALUES ( \(.oracle_id | tosql),"
+"\((.published_at / 1000) | todateiso8601 | tosql),"
+"\(.ruling_text | tosql) );"
)

)'

echo "COMMIT;"
