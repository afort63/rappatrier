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
    zenity --info --title="Paramètres" --width=400 --height=200 \
        --text="REPERTOIRE_DISTANT : $REPERTOIRE_DISTANT
REPERTOIRE_LOCAL : $REPERTOIRE_LOCAL"
}

# Fonction pour récupérer la liste des fichiers (date, heure, nom, lien, extension)
recuperer_fichiers_distants() {
    load_params
    curl -s "${REPERTOIRE_DISTANT%/}/" | \
        grep -oP '<br>\K(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2})\s+[0-9]+\s+<A HREF="([^"]+)">([^<]+)</A>' | \
        sed -E 's#([0-9/]+)\s+([0-9:]+)\s+[0-9]+\s+<A HREF="([^"]+)">([^<]+)</A>#\1|\2|\4|\3#' | \
        awk -F\| '{
            ext="";
            if (match($3, /\.([^.]+)$/)) ext=substr($3,RSTART+1,RLENGTH-1);
            print $1 "|" $2 "|" $3 "|" $4 "|" ext;
        }'
}

# Affichage de la liste complète avec tri par colonne (Zenity)
choisir_fichiers_a_recuperer() {
    load_params
    fichiers_brut=$(recuperer_fichiers_distants)
    if [[ -z "$fichiers_brut" ]]; then
        zenity --error --text="Aucun fichier trouvé dans le répertoire distant."
        return
    fi

    noms=()
    dates=()
    heures=()
    liens=()
    exts=()

    while IFS="|" read -r date heure nom lien ext; do
        noms+=("$nom")
        dates+=("$date")
        heures+=("$heure")
        liens+=("$lien")
        exts+=("$ext")
    done <<< "$fichiers_brut"

    n=${#noms[@]}
    if [[ $n -eq 0 ]]; then
        zenity --error --text="Aucun fichier exploitable trouvé dans l'index."
        return
    fi

    zenity_args=()
    for ((i = 0; i < n; i++)); do
        # On ajoute le lien en dernière colonne cachée
        zenity_args+=("${noms[i]}" "${dates[i]}" "${heures[i]}" "${exts[i]}" "${liens[i]}")
    done

    selection=$(zenity --list \
        --title="Fichiers distants à récupérer" \
        --text="Sélectionnez les fichiers à récupérer (tri possible par colonne) :" \
        --width=1000 \
        --height=600 \
        --multiple \
        --separator="|" \
        --column="Nom du fichier" --column="Date" --column="Heure" --column="Extension" --column="Lien" \
        --hide-column=5 \
        "${zenity_args[@]}")

    if [[ -z "$selection" ]]; then
        return
    fi

    # On transforme la sélection en tableau pour retrouver les liens correspondant
    IFS="|" read -ra selected <<< "$selection"
    nbcol=5
    selected_names=()
    selected_links=()
    for ((i=0; i<${#selected[@]}; i+=nbcol)); do
        selected_names+=("${selected[i]}")
        selected_links+=("${selected[i+4]}")
    done

    lancer_telechargement_fichiers "${selected_names[@]}" ";;;" "${selected_links[@]}"
}

lancer_telechargement_fichiers() {
    # $@ = noms;;;liens (séparateur ";;;")
    load_params
    # On sépare noms et liens
    args=("$@")
    split_idx=0
    for idx in "${!args[@]}"; do
        if [[ "${args[$idx]}" == ";;;" ]]; then
            split_idx=$idx
            break
        fi
    done

    total=$split_idx
    count=0

    (
    for ((i=0; i<$total; i++)); do
        nom="${args[$i]}"
        lien="${args[$((split_idx+1+i))]}"
        ((count++))
        url="${REPERTOIRE_DISTANT%/}/$lien"
        wget -q -O "${REPERTOIRE_LOCAL%/}/$nom" "$url"
        pct=$(( 100 * count / total ))
        echo "$pct"
        echo "# Téléchargement de $nom ($count/$total)"
    done
    ) | zenity --progress --title="Téléchargement ciblé" --text="Téléchargement des fichiers sélectionnés..." --percentage=0 --auto-close

    if [[ $? -eq 0 ]]; then
        zenity --info --text="Téléchargement terminé !"
    else
        zenity --error --text="Erreur lors du téléchargement."
    fi
}

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

    save_params

    choisir_fichiers_a_recuperer
}

while true; do
    choix=$(zenity --list --title="Menu principal" \
        --text="Sélectionnez une action :" \
        --radiolist \
        --column="Choix" --column="Action" \
        TRUE "Choix des fichiers à récupérer" \
        FALSE "Paramètres" \
        FALSE "Quitter" \
        --width=400 --height=200)

    case "$choix" in
        "Choix des fichiers à récupérer")
            lancer_copie
            ;;
        "Paramètres")
            afficher_parametres
            ;;
        "Quitter"|"")
            break
            ;;
    esac
done
