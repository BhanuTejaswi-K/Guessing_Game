#!/bin/bash

secret_number=$(( RANDOM % 1000 + 1 ))
number_of_guesses=0

echo "Enter your username:"
read -r username

if [[ -z "$username" || ${#username} -gt 22 ]]; then
  echo "Username must be between 1 and 22 characters."
  exit 1
fi

if ! user_stats=$(psql -X -qAt -v ON_ERROR_STOP=1 -U freecodecamp -d number_guess \
  -v username="$username" <<'SQL'
SELECT games_played || '|' || COALESCE(best_game::text, '')
FROM users
WHERE username = :'username';
SQL
); then
  exit 1
fi

if [[ -z "$user_stats" ]]; then
  if ! psql -X -q -v ON_ERROR_STOP=1 -U freecodecamp -d number_guess \
    -v username="$username" >/dev/null <<'SQL'
INSERT INTO users (username) VALUES (:'username') ON CONFLICT (username) DO NOTHING;
SQL
  then
    exit 1
  fi
  echo "Welcome, $username! It looks like this is your first time here."
else
  IFS='|' read -r games_played best_game <<< "$user_stats"
  echo "Welcome back, $username! You have played $games_played games, and your best game took $best_game guesses."
fi

echo "Guess the secret number between 1 and 1000:"

while true; do
  if ! read -r guess; then
    exit 1
  fi

  if [[ ! "$guess" =~ ^[+-]?[0-9]+$ ]]; then
    echo "That is not an integer, guess again:"
    continue
  fi

  number_of_guesses=$((number_of_guesses + 1))
  normalized_guess=$guess
  if [[ "$normalized_guess" == -* ]]; then
    numeric_guess=-1
  else
    if [[ "$normalized_guess" == +* ]]; then
      normalized_guess=${normalized_guess:1}
    fi
    while [[ ${#normalized_guess} -gt 1 && ${normalized_guess:0:1} == 0 ]]; do
      normalized_guess=${normalized_guess:1}
    done

    if [[ ${#normalized_guess} -gt 4 ]]; then
      numeric_guess=1001
    else
      numeric_guess=$((10#$normalized_guess))
    fi
  fi

  if (( numeric_guess == secret_number )); then
    if ! psql -X -q -v ON_ERROR_STOP=1 -U freecodecamp -d number_guess \
      -v username="$username" -v guesses="$number_of_guesses" >/dev/null <<'SQL'
UPDATE users
SET games_played = games_played + 1,
    best_game = CASE WHEN best_game IS NULL OR :guesses < best_game THEN :guesses ELSE best_game END
WHERE username = :'username';
SQL
    then
      exit 1
    fi
    echo "You guessed it in $number_of_guesses tries. The secret number was $secret_number. Nice job!"
    break
  elif (( numeric_guess < secret_number )); then
    echo "It's higher than that, guess again:"
  else
    echo "It's lower than that, guess again:"
  fi
done