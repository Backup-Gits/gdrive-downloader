#!/usr/bin/env sh
# shellcheck source=/dev/null

###################################################
# Download a gdrive file
# Todo: write doc
###################################################
_download_file() {
    [ $# -lt 3 ] && printf "Missing arguments\n" && return 1
    file_id_download_file="${1}" name_download_file="${2}" server_size_download_file="${3}" parallel_download_file="${4}" \
        use_aria_download_file="${DOWNLOAD_WITH_ARIA}"
    unset range_download_file downloaded_download_file old_downloaded_download_file left_download_file speed_download_file eta_download_file \
        flag_download_file flag_value_download_file url_download_file cookies_download_file

    server_size_readable_download_file="$(_bytes_to_human "${server_size_download_file}")"
    _print_center "justify" "${name_download_file}" " | ${server_size_download_file:+${server_size_readable_download_file}}" "="

    # URL="${API_URL}/drive/${API_VERSION}/files/${file_id_download_file}?alt=media&key=${API_KEY}" ( downloading with api )

    if [ -s "${name_download_file}" ]; then
        local_size_download_file="$(_actual_size_in_bytes "${name_download_file}")"

        if [ "${local_size_download_file}" -ge "${server_size_download_file}" ]; then
            "${QUIET:-_print_center}" "justify" "File already present" "=" && _newline "\n"
            _log_in_file
            return 0
        else
            _print_center "justify" "File is partially" " present, resuming.." "-"
            range_download_file="Range: bytes=${local_size_download_file}-${server_size_download_file}"
            # aria can only resume downloads if either oauth or api key download method is used.
            [ -z "${OAUTH_ENABLED:-${API_KEY_DOWNLOAD}}" ] && unset use_aria_download_file
        fi
    else
        [ "${server_size_download_file}" -gt 0 ] && range_download_file="Range: bytes=0-${server_size_download_file}"
        _print_center "justify" "Downloading file.." "-"
    fi

    # download with oauth creds if enabled
    if [ -n "${OAUTH_ENABLED}" ]; then
        . "${TMPFILE}_ACCESS_TOKEN"
        flag_download_file="--header" flag_value_download_file="Authorization: Bearer ${ACCESS_TOKEN}"
        url_download_file="${API_URL}/drive/${API_VERSION}/files/${file_id_download_file}?alt=media&supportsAllDrives=true&includeItemsFromAllDrives=true"
    elif [ -n "${API_KEY_DOWNLOAD}" ]; then
        # download with api key
        flag_download_file="--referer" flag_value_download_file="https://drive.google.com"
        url_download_file="${API_URL}/drive/${API_VERSION}/files/${file_id_download_file}?alt=media&supportsAllDrives=true&includeItemsFromAllDrives=true&key=${API_KEY}"
    else
        # normal downloading
        "${EXTRA_LOG}" "justify" "Fetching" " cookies.." "-"
        # shellcheck disable=SC2086
        curl -c "${TMPFILE}_${file_id_download_file}_COOKIE" -I ${CURL_PROGRESS} -o /dev/null "https://drive.google.com/uc?export=download&id=${file_id_download_file}" || :
        for _ in 1 2; do _clear_line 1; done
        confirm_string="$(_tmp="$(grep -F 'download_warning' "${TMPFILE}_${file_id_download_file}_COOKIE")" && printf "%s\n" "${_tmp##*$(printf '\t')}")" || :

        flag_download_file="-b" flag_value_download_file="${TMPFILE}_${file_id_download_file}_COOKIE"

        # aria need some elements removed from cookies when it is generated by curl
        [ -n "${use_aria_download_file}" ] && {
            cookies_download_file="$(sed -e "s/^\# .*//g" -e "s/^\#HttpOnly_//g" "${TMPFILE}_${file_id_download_file}_COOKIE")"
            printf "%s\n" "${cookies_download_file}" >| "${TMPFILE}_${file_id_download_file}_COOKIE"
            flag_download_file="--load-cookies"
        }

        url_download_file="https://drive.google.com/uc?export=download&id=${file_id_download_file}${confirm_string:+&confirm=${confirm_string}}"
    fi

    if [ -n "${use_aria_download_file}" ]; then
        # shellcheck disable=SC2086
        aria2c ${SPEED_LIMIT:+${ARIA_SPEED_LIMIT_FLAG}} ${SPEED_LIMIT} ${ARIA_EXTRA_FLAGS} \
            "${flag_download_file}" "${flag_value_download_file}" \
            "${url_download_file}" -o "${name_download_file}" &
        pid="${!}"
    else
        # shellcheck disable=SC2086
        curl ${SPEED_LIMIT:+${CURL_SPEED_LIMIT_FLAG}} ${SPEED_LIMIT} ${CURL_EXTRA_FLAGS} \
            --header "${range_download_file}" \
            "${flag_download_file}" "${flag_value_download_file}" \
            "${url_download_file}" >> "${name_download_file}" &
        pid="${!}"
    fi

    if [ -n "${parallel_download_file}" ]; then
        wait "${pid}" 2>| /dev/null 1>&2
    else
        until [ -f "${name_download_file}" ]; do sleep 0.5; done

        _newline "\n\n"
        until ! kill -0 "${pid}" 2>| /dev/null 1>&2; do
            downloaded_download_file="$(_actual_size_in_bytes "${name_download_file}")"
            left_download_file="$((server_size_download_file - downloaded_download_file))"
            speed_download_file="$((downloaded_download_file - old_downloaded_download_file))"
            { [ "${speed_download_file}" -gt 0 ] && eta_download_file="$(_display_time "$((left_download_file / speed_download_file))")"; } || eta_download_file=""
            sleep 0.5
            _move_cursor 2
            ##################################################### Amount Downloaded ####################### Amount left to download ##################
            _print_center "justify" "Downloaded: $(_bytes_to_human "${downloaded_download_file}") " "| Left: $(_bytes_to_human "${left_download_file}")" "="
            ########################################### Speed of download ############### ETA ######################
            _print_center "justify" "Speed: $(_bytes_to_human "${speed_download_file}")/s " "| ETA: ${eta_download_file:-Unknown}" "-"
            old_downloaded_download_file="${downloaded_download_file}"
        done
    fi

    if [ "$(_actual_size_in_bytes "${name_download_file}")" -ge "${server_size_download_file}" ]; then
        for _ in 1 2 3; do _clear_line 1; done
        "${QUIET:-_print_center}" "justify" "Downloaded" "=" && _newline "\n"
        rm -f "${name}.aria2"
    else
        "${QUIET:-_print_center}" "justify" "Error: Incomplete" " download." "=" 1>&2
        return 1
    fi
    _log_in_file "${name_download_file}" "${server_size_readable_download_file}" "${file_id_download_file}"
    return 0
}

###################################################
# A extra wrapper for _download_file function to properly handle retries
# also handle uploads in case downloading from folder
# Todo: write doc
###################################################
_download_file_main() {
    [ $# -lt 2 ] && printf "Missing arguments\n" && return 1
    unset line_download_file_main fileid_download_file_main name_download_file_main size_download_file_main parallel_download_file_main RETURN_STATUS sleep_download_file_main && retry_download_file_main="${RETRY:-0}"
    [ "${1}" = parse ] && parallel_download_file_main="${3}" line_download_file_main="${2}" fileid_download_file_main="${line_download_file_main%%"|:_//_:|"*}" \
        name_download_file_main="${line_download_file_main##*"|:_//_:|"}" size_download_file_main="$(_tmp="${line_download_file_main#*"|:_//_:|"}" && printf "%s\n" "${_tmp%"|:_//_:|"*}")"
    parallel_download_file_main="${parallel_download_file_main:-${5}}"

    unset RETURN_STATUS && until [ "${retry_download_file_main}" -le 0 ] && [ -n "${RETURN_STATUS}" ]; do
        if [ -n "${parallel_download_file_main}" ]; then
            _download_file "${fileid_download_file_main:-${2}}" "${name_download_file_main:-${3}}" "${size_download_file_main:-${4}}" true 2>| /dev/null 1>&2 && RETURN_STATUS=1 && break
        else
            _download_file "${fileid_download_file_main:-${2}}" "${name_download_file_main:-${3}}" "${size_download_file_main:-${4}}" && RETURN_STATUS=1 && break
        fi
        sleep "$((sleep_download_file_main += 1))" # on every retry, sleep the times of retry it is, e.g for 1st, sleep 1, for 2nd, sleep 2
        RETURN_STATUS=2 retry_download_file_main="$((retry_download_file_main - 1))" && continue
    done
    { [ "${RETURN_STATUS}" = 1 ] && printf "%b" "${parallel_download_file_main:+${RETURN_STATUS}\n}"; } || printf "%b" "${parallel_download_file_main:+${RETURN_STATUS}\n}" 1>&2
    return 0
}

###################################################
# Download a gdrive folder along with sub folders
# File IDs are fetched inside the folder, and then downloaded seperately.
# Todo: write doc
###################################################
_download_folder() {
    [ $# = 0 ] && printf "Missing arguments\n" && return 1
    folder_id_download_folder="${1}" name_download_folder="${2}" parallel_download_folder="${3}"
    unset json_search_download_folder json_search_fragment_download_folder next_page_token \
        error_status_download_folder success_status_download_folder \
        files_download_folder folders_download_folder files_size_download_folder files_name_download_folder folders_name_download_folder \
        num_of_files_download_folder num_of_folders_download_folder
    _newline "\n"
    "${EXTRA_LOG}" "justify" "${name_download_folder}" "="
    "${EXTRA_LOG}" "justify" "Fetching folder" " details.." "-"
    _search_error_message_download_folder() {
        "${QUIET:-_print_center}" "justify" "Error: Cannot" ", fetch folder details." "="
        printf "%s\n" "${1:?}" && return 1
    }

    # do the first request with pagesize 1000, and fetch nextPageToken
    if json_search_download_folder="$("${API_REQUEST_FUNCTION}" "files?q=%27${folder_id_download_folder}%27+in+parents&fields=nextPageToken,files(name,size,id,mimeType)&pageSize=1000")"; then
        # fetch next page jsons till nextPageToken is available
        until ! next_page_token="$(printf "%s\n" "${json_search_fragment_download_folder:-${json_search_download_folder}}" | _json_value nextPageToken 1 1)"; do
            json_search_fragment_download_folder="$("${API_REQUEST_FUNCTION}" "files?q=%27${folder_id_download_folder}%27+in+parents&fields=nextPageToken,files(name,size,id,mimeType)&pageSize=1000&pageToken=${next_page_token}")" ||
                _search_error_message_download_folder "${json_search_fragment_download_folder}"

            # append the new fetched json to initial json
            json_search_download_folder="${json_search_download_folder}
${json_search_fragment_download_folder}"
        done
    else
        # error message in case some thing goes wrong
        _search_error_message_download_folder "${json_search_download_folder}"
    fi && _clear_line 1

    # parse the fetched json and make a list containing files size, name and id
    "${EXTRA_LOG}" "justify" "Preparing files list.." "="
    files_download_folder="$(printf "%s\n" "${json_search_download_folder}" | grep '"size":' -B3 | _json_value id all all)" || :
    files_size_download_folder="$(printf "%s\n" "${json_search_download_folder}" | _json_value size all all)" || :
    files_name_download_folder="$(printf "%s\n" "${json_search_download_folder}" | grep size -B2 | _json_value name all all)" || :
    exec 5<< EOF
$(printf "%s\n" "${files_download_folder}")
EOF
    exec 6<< EOF
$(printf "%s\n" "${files_size_download_folder}")
EOF
    exec 7<< EOF
$(printf "%s\n" "${files_name_download_folder}")
EOF
    files_list_download_folder="$(while read -r id <&5 && read -r size <&6 && read -r name <&7; do
        printf "%s\n" "${id}|:_//_:|${size}|:_//_:|${name}"
    done)"
    exec 5<&- && exec 6<&- && exec 7<&-
    _clear_line 1

    # parse the fetched json and make a list containing sub folders name and id
    "${EXTRA_LOG}" "justify" "Preparing sub folders list.." "="
    folders_download_folder="$(printf "%s\n" "${json_search_download_folder}" | grep '"mimeType":.*folder.*' -B2 | _json_value id all all)" || :
    folders_name_download_folder="$(printf "%s\n" "${json_search_download_folder}" | grep '"mimeType":.*folder.*' -B1 | _json_value name all all)" || :
    exec 5<< EOF
$(printf "%s\n" "${folders_download_folder}")
EOF
    exec 6<< EOF
$(printf "%s\n" "${folders_name_download_folder}")
EOF
    folders_list_download_folder="$(while read -r id <&5 && read -r name <&6; do
        printf "%s\n" "${id}|:_//_:|${name}"
    done)"
    exec 5<&- && exec 6<&-
    _clear_line 1

    if [ -z "${files_download_folder:-${folders_download_folder}}" ]; then
        for _ in 1 2; do _clear_line 1; done && _print_center "justify" "${name_download_folder}" " | Empty Folder" "=" && _newline "\n" && return 0
    fi
    [ -n "${files_download_folder}" ] && num_of_files_download_folder="$(($(printf "%s\n" "${files_download_folder}" | wc -l)))"
    [ -n "${folders_download_folder}" ] && num_of_folders_download_folder="$(($(printf "%s\n" "${folders_download_folder}" | wc -l)))"

    for _ in 1 2; do _clear_line 1; done
    _print_center "justify" \
        "${name_download_folder}" \
        "${num_of_files_download_folder:+ | ${num_of_files_download_folder} files}${num_of_folders_download_folder:+ | ${num_of_folders_download_folder} sub folders}" "=" &&
        _newline "\n\n"

    if [ -f "${name_download_folder}" ]; then
        name_download_folder="${name_download_folder}$(date +'%s')"
    fi && mkdir -p "${name_download_folder}"

    cd "${name_download_folder}" || exit 1

    if [ -n "${num_of_files_download_folder}" ]; then
        if [ -n "${parallel_download_folder}" ]; then
            NO_OF_PARALLEL_JOBS_FINAL="$((NO_OF_PARALLEL_JOBS > num_of_files_download_folder ? num_of_files_download_folder : NO_OF_PARALLEL_JOBS))"

            [ -f "${TMPFILE}"SUCCESS ] && rm "${TMPFILE}"SUCCESS
            [ -f "${TMPFILE}"ERROR ] && rm "${TMPFILE}"ERROR

            # shellcheck disable=SC2016
            (printf "%s\n" "${files_list_download_folder}" | xargs -n1 -P"${NO_OF_PARALLEL_JOBS_FINAL}" -i sh -c '
                eval "${SOURCE_UTILS}"
                _download_file_main parse "{}" true
                ' 1>| "${TMPFILE}"SUCCESS 2>| "${TMPFILE}"ERROR) &
            pid="${!}"

            until [ -f "${TMPFILE}"SUCCESS ] || [ -f "${TMPFILE}"ERROR ]; do sleep 0.5; done

            _clear_line 1
            until ! kill -0 "${pid}" 2>| /dev/null 1>&2; do
                success_status_download_folder="$(($(wc -l < "${TMPFILE}"SUCCESS)))"
                error_status_download_folder="$(($(wc -l < "${TMPFILE}"ERROR)))"
                sleep 1
                if [ "$((success_status_download_folder + error_status_download_folder))" != "${TOTAL}" ]; then
                    printf '%s\r' "$(_print_center "justify" "Status" ": ${success_status_download_folder:-0} Downloaded | ${error_status_download_folder:-0} Failed" "=")"
                fi
                TOTAL="$((success_status_download_folder + error_status_download_folder))"
            done
            _newline "\n"
            success_status_download_folder="$(($(wc -l < "${TMPFILE}"SUCCESS)))"
            error_status_download_folder="$(($(wc -l < "${TMPFILE}"ERROR)))"
            _clear_line 1 && _newline "\n"
        else
            while read -r line <&4 && { [ -n "${line}" ] || continue; }; do
                _download_file_main parse "${line}"
                : "$((RETURN_STATUS < 2 ? (success_status_download_folder += 1) : (error_status_download_folder += 1)))"
                if [ -z "${VERBOSE}" ]; then
                    for _ in 1 2 3 4; do _clear_line 1; done
                fi
                _print_center "justify" "Status" ": ${success_status_download_folder:-0} Downloaded | ${error_status_download_folder:-0} Failed" "="
            done 4<< EOF
$(printf "%s\n" "${files_list_download_folder}")
EOF
        fi
    fi

    for _ in 1 2; do _clear_line 1; done
    [ "${success_status_download_folder}" -gt 0 ] && "${QUIET:-_print_center}" "justify" "Downloaded" ": ${success_status_download_folder}" "="
    [ "${error_status_download_folder:-0}" -gt 0 ] && "${QUIET:-_print_center}" "justify" "Failed" ": ${error_status_download_folder}" "="
    _newline "\n"

    if [ -z "${SKIP_SUBDIRS}" ] && [ -n "${num_of_folders_download_folder}" ]; then
        while read -r line <&4 && { [ -n "${line}" ] || continue; }; do
            (_download_folder "${line%%"|:_//_:|"*}" "${line##*"|:_//_:|"}" "${parallel:-}")
        done 4<< EOF
$(printf "%s\n" "${folders_list_download_folder}")
EOF
    fi

    cd - 2>| /dev/null 1>&2 || exit 1

    return 0
}

###################################################
# Log downloaded file info in case of -l / --log flag
# Todo: write doc
###################################################
_log_in_file() {
    [ -z "${LOG_FILE_ID}" ] || [ -d "${LOG_FILE_ID}" ] && return 0
    # shellcheck disable=SC2129
    # https://github.com/koalaman/shellcheck/issues/1202#issuecomment-608239163
    {
        printf "%s\n" "Name: ${1}"
        printf "%s\n" "Size: ${2}"
        printf "%s\n\n" "ID: ${3}"
    } >> "${LOG_FILE_ID}"
}
