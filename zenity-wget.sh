#!/bin/bash

PARAM_FILE="param.conf"

load_params() {
    if [[ -f "$PARAM_FILE" ]]; then
        source "$PARAM_FILE"
    else
        REPERTOIRE_DISTANT=""
        REPERTOIRE_LOCAL=""
    fi
}

save_params() {
    echo "REPERTOIRE_DISTANT=\"$REPERTOIRE_DISTANT\"" > "$PARAM_FILE"
    echo "REPERTOIRE_LOCAL=\"$REPERTOIRE_LOCAL\"" >> "$PARAM_FILE"
}

afficher_parametres() {
    load_params
    params_text="REPERTOIRE_DISTANT : $REPERTOIRE_DISTANT
REPERTOIRE_LOCAL : $REPERTOIRE_LOCAL"
    zenity --info --title="Paramètres" --width=400 --height=200 --text="$params_text"
}

# Fonction pour lister les fichiers distants selon ton format HTML
lister_fichiers_distants() {
    load_params
    fichiers=$(curl -s "$REPERTOIRE_DISTANT" | \
        grep -oP '<A HREF="[^"]+">.*?</A>' | \
        sed -E 's/<A HREF="([^"]+)">([^<]+)<\/A>/\2|\/\1/')
    echo "$fichiers"
}

# Fonction pour choisir les fichiers à récupérer
choisir_fichiers_a_recuperer() {
    load_params
    fichiers=$(lister_fichiers_distants)
    if [[ -z "$fichiers" ]]; then
        zenity --error --text="Aucun fichier trouvé dans le répertoire distant."
        return
    fi

    # On sépare noms et liens pour Zenity (affichage du nom, on garde le lien pour plus tard)
    noms=()
    liens=()
    while IFS="|" read -r nom lien; do
        noms+=("$nom")
        liens+=("$lien")
    done <<< "$fichiers"

    selection=$(zenity --list \
        --title="Fichiers distants à récupérer" \
        --text="Sélectionnez les fichiers à récupérer :" \
        --width=700 \
        --height=400 \
        --multiple \
        --separator="|" \
        --column="Nom du fichier" "${noms[@]}")

    if [[ -n "$selection" ]]; then
        zenity --info --text="Vous avez sélectionné :\n$selection"
        # On pourra ensuite télécharger les fichiers sélectionnés
        # (à implémenter plus tard)
    fi
}

# Lancer la copie (fonction inchangée)
lancer_copie() {
    load_params

    REPERTOIRE_DISTANT=$(zenity --entry \
        --title="Répertoire distant" \
        --text="Entrez l'URL du répertoire distant (ou chemin) à récupérer" \
        --entry-text="$REPERTOIRE_DISTANT")
    if [[ -z "$REPERTOIRE_DISTANT" ]]; then
        zenity --error --text="Répertoire distant non renseigné. Sortie."
        return
    fi

    REPERTOIRE_LOCAL=$(zenity --file-selection --directory \
        --title="Sélectionnez le répertoire local de destination" \
        ${REPERTOIRE_LOCAL:+--filename="$REPERTOIRE_LOCAL"})
    if [[ -z "$REPERTOIRE_LOCAL" ]]; then
        zenity --error --text="Répertoire local non renseigné. Sortie."
        return
    fi

    if [[ ! -d "$REPERTOIRE_LOCAL" ]]; then
        zenity --warning --text="Le répertoire local n'existe pas. Il va être créé."
        mkdir -p "$REPERTOIRE_LOCAL"
        if [[ $? -ne 0 ]]; then
            zenity --error --text="Impossible de créer le répertoire local. Sortie."
            return
        fi
    fi

    save_params # Mémorise le dernier usage

    (
        wget -r -np -nH --cut-dirs=1 -P "$REPERTOIRE_LOCAL" "$REPERTOIRE_DISTANT"
    ) | zenity --progress --title="Téléchargement en cours" --text="wget télécharge les fichiers..." --pulsate --auto-close

    if [[ $? -eq 0 ]]; then
        zenity --info --text="Téléchargement terminé !"
    else
        zenity --error --text="Erreur lors du téléchargement."
    fi
}

# Menu principal
while true; do
    choix=$(zenity --list --title="Menu principal" \
        --text="Sélectionnez une action :" \
        --radiolist \
        --column="Choix" --column="Action" \
        TRUE "Choix des fichiers à récupérer" \
        FALSE "Paramètres" \
        FALSE "Quitter")

    case "$choix" in
        "Choix des fichiers à récupérer")
            choisir_fichiers_a_recuperer
            ;;
        "Paramètres")
            afficher_parametres
            ;;
        "Quitter"|"")
            break
            ;;
    esac
done
