#!/bin/sh
# Exit script on error
set -e
# Exit on variable not set
set -u
# Set locale to POSIX
LC_ALL=C
export LC_ALL
#-------------------------------------------------------------------------------
# https://sources.debian.org/doc/api/
debian_src_api_url='https://sources.debian.org/api'
# Debian GitLab
debian_salsa_api_url_base='https://salsa.debian.org/api/v4'
debian_gcc_repo_url="$debian_salsa_api_url_base/projects/toolchain-team%2Fgcc/repository"
debian_archive_dists_url='https://deb.debian.org/debian/dists'
# https://www.debian.org/doc/debian-policy/ch-controlfields.html#version
package_version_regex='\([0-9]\+:\)\?[0-9][0-9A-Za-z.~+-]*'
# https://docs.docker.com/docker-hub/api/latest/
docker_api_url_base='https://hub.docker.com/v2'
docker_api_url_debian="$docker_api_url_base/namespaces/library/repositories/debian"
docker_api_url_debian_tags="$docker_api_url_debian/tags"
docker_debian_repo='docker.io/library/debian'
#-------------------------------------------------------------------------------
# fetch_suite_list()
#-------------------------------------------------------------------------------
fetch_suite_list() {
    curl \
        --location \
        --silent \
        --url "$debian_archive_dists_url/README" \
    | sed \
        --expression='s/\s*\([^,]\+\)\s*,\s*or\s*\([A-Za-z-]\+\).*/\1=\2/p' \
        --silent
}
#-------------------------------------------------------------------------------
# fetch_suite_data()
#-------------------------------------------------------------------------------
fetch_suite_data() {
    _suite="$1"
    _url_base="$debian_archive_dists_url/$_suite"
    _release_url="$_url_base/Release"
    # _inrelease_url="$_url_base/InRelease"
    curl \
        --location \
        --range 0-512 \
        --silent \
        --url "$_release_url"
}
#-------------------------------------------------------------------------------
# parse_suite_data()
#-------------------------------------------------------------------------------
parse_suite_data() {
    _data="$1"
    _field="$2"
    printf '%s' "$_data" | sed \
        --expression='s/\s*'"$_field"'\s*:\s*\(.\+\)\s*/\1/p' \
        --silent
}
#-------------------------------------------------------------------------------
# fetch_image_tag()
#-------------------------------------------------------------------------------
fetch_image_tag() {
    _tag="$1-slim"
    _status_code="$(curl \
        --head \
        --location \
        --output '/dev/null' \
        --silent \
        --url "$docker_api_url_debian_tags/$_tag" \
        --write-out '%{http_code}' \
    )"
    if [ "$_status_code" = '200' ]; then
        printf '%s' "$_tag"
    else
        printf ''
    fi
}
#-------------------------------------------------------------------------------
# update_suites()
#-------------------------------------------------------------------------------
update_suites() {
    _path="$1"
    rm --force "$_path"
    _suite_list="$(fetch_suite_list)"
    printf '[' >> "$_path"
    for _line in $_suite_list; do
        _suite="$(printf '%s' "$_line" | sed \
            --expression='s/\(.\+\)=.\+/\1/p' \
            --silent \
        )"
        _codename="$(printf '%s' "$_line" | sed \
            --expression='s/.\+=\(.\+\)/\1/p' \
            --silent \
        )"
        _data="$(fetch_suite_data "$_suite")"
        _version="$(parse_suite_data "$_data" 'Version')"
        _date="$(parse_suite_data "$_data" 'Date')"
        if [ -n "$_date" ]; then
            _date="$(date --iso-8601=seconds --utc --date "$_date")"
        fi
        _valid_until="$(parse_suite_data "$_data" 'Valid-Until')"
        if [ -n "$_valid_until" ]; then
            _valid_until="$(date --iso-8601=seconds --utc --date "$_valid_until")"
        fi
        _tag="$_version"
        if [ -z "$_tag" ]; then
            _tag="$_codename"
        fi
        _image_tag="$(fetch_image_tag "$_tag")"
        printf '{"suite":"%s","codename":"%s","version":"%s","date":"%s","valid_until":"%s","image_tag":"%s"},\n' \
            "$_suite" "$_codename" "$_version" "$_date" "$_valid_until" "$_image_tag" \
        >> "$_path"
    done
    sed --expression='$s/,$/]/' --in-place "$_path"
}
#-------------------------------------------------------------------------------
# fetch_gcc_version_major_list()
#-------------------------------------------------------------------------------
fetch_gcc_version_major_list() {
    curl \
        --location \
        --silent \
        --url "$debian_src_api_url/search/gcc/" \
    | sed \
        --expression='s/[^"]*"name"\s*:\s*"\(gcc-[^"]\+\)"/\1\n/gp' \
        --silent \
    | sed \
        --expression='s/.*gcc-\([0-9]\+\)$/\1/p' \
        --silent \
    | sort \
        --numeric-sort
}
#-------------------------------------------------------------------------------
# fetch_gcc_data()
#-------------------------------------------------------------------------------
fetch_gcc_data() {
    _version_major="$1"
    _codename="$2"
    _url_base="$debian_src_api_url/src/gcc-$_version_major"
    _url="$_url_base/?suite=$_codename"
    if [ "$_codename" = 'latest' ]; then
        _url="$_url_base/latest/"
    fi
    printf '%s' "$(curl --location --silent --url "$_url")"
}
#-------------------------------------------------------------------------------
# fetch_gcc_revision()
#-------------------------------------------------------------------------------
fetch_gcc_revision() {
    _version="$1"
    _revision=
    if [ -n "$_version" ]; then
        _revision="$( \
            curl \
                --silent \
                --url "$debian_gcc_repo_url/commits?ref_name=$_version&per_page=1" \
            | sed \
                --expression 's/.*"id"\s*:\s*"\([0-9a-zA-Z]\+\)".*/\1/p' \
                --silent \
        )"
    fi
    printf '%s' "$_revision"
}
#-------------------------------------------------------------------------------
# parse_gcc_version()
#-------------------------------------------------------------------------------
parse_gcc_version() {
    _data="$1"
    printf '%s' "$_data" | sed \
        --expression='s/[^"]\+"version"\s*:\s*"\('"$package_version_regex"'\)".*/version=\1/' \
        --expression='s/.\+version=\(.\+\)/\1/p' \
        --silent
}
#-------------------------------------------------------------------------------
# parse_suite()
#-------------------------------------------------------------------------------
parse_suite() {
    _data="$1"
    printf '%s' "$_data" | sed \
        --expression='s/.\+"suites"\s*:\s*\[\s*"\([^"]*\).\+/\1/p' \
        --silent
}
#-------------------------------------------------------------------------------
# get_codename_from_suite()
#-------------------------------------------------------------------------------
get_codename_from_suite() {
    _suites_data="$1"
    _suite="$2"
    printf '%s' "$_suites_data" | sed \
        --expression='s/.\+"suite":"'"$_suite"'".\+"codename":"\([^"]\+\)".\+/\1/p' \
        --silent
}
#-------------------------------------------------------------------------------
# get_image_tag_from_codename()
#-------------------------------------------------------------------------------
get_image_tag_from_codename() {
    _suites_data="$1"
    _codename="$2"
    printf '%s' "$_suites_data" | sed \
        --expression='s/.\+"codename":"'"$_codename"'".\+"image_tag":"\([^"]\+\)".\+/\1/p' \
        --silent
}
#-------------------------------------------------------------------------------
# update_versions()
#-------------------------------------------------------------------------------
update_versions() {
    _path="$1"
    _suites_data="$2"
    rm --force "$_path"
    _version_major_list="$(fetch_gcc_version_major_list)"
    _stable="$(get_codename_from_suite "$_suites_data" 'stable')"
    _testing="$(get_codename_from_suite "$_suites_data" 'testing')"
    _codename_list="$_stable $_testing latest"
    printf '[' >> "$_path"
    for _version_major in $_version_major_list; do
        for _codename in $_codename_list; do
            _gcc_data="$(fetch_gcc_data "$_version_major" "$_codename")"
            _version="$(parse_gcc_version "$_gcc_data")"
            if [ -n "$_version" ]; then
                break
            fi
        done
        if [ "$_codename" = 'latest' ]; then
            _codename="$(parse_suite "$_gcc_data")"
            if [ "$_codename" = 'experimental' ]; then
                _codename="$(get_codename_from_suite "$_suites_data" 'experimental')"
            fi
        fi
        _revision="$(fetch_gcc_revision "$_version")"
        _image_tag="$(get_image_tag_from_codename "$_suites_data" "$_codename")"
        printf '{"version":"%s","revision":"%s","image_tag":"%s"},\n' \
            "$_version" "$_revision" "$_image_tag" \
        >> "$_path"
    done
    sed --expression='$s/,$/]/' --in-place "$_path"
}
#-------------------------------------------------------------------------------
# generate_dockerfiles()
#-------------------------------------------------------------------------------
generate_dockerfiles() {
    _versions_data="$1"
    for _line in $_versions_data; do
        _image_tag="$(printf '%s' "$_line" | sed \
            --expression='s/.\+"image_tag":"\([^"]\+\)".\+/\1/p' \
            --silent
        )"
        if [ -z "$_image_tag" ]; then
            continue
        fi
        _image="$docker_debian_repo:$_image_tag"
        _gcc_version_major="$(printf '%s' "$_line" | sed \
            --expression='s/.\+"version":"\([0-9]\+\)[^"]\+".\+/\1/p' \
            --silent \
        )"
        sed "./gcc-slim.template" \
            --expression="s|@IMAGE@|$_image|" \
            --expression="s/@GCC_VERSION_MAJOR@/$_gcc_version_major/" \
            > "./gcc-slim-$_gcc_version_major.dockerfile"
    done
}
#-------------------------------------------------------------------------------
# build_images()
#-------------------------------------------------------------------------------
build_images() {
    _data="$1"
    _url='https://gitlab.com/sequpt/containers'
    _dockerfile_list="$(find '.' -type 'f' -name 'gcc-slim-*.dockerfile' | sort --version-sort)"
    for _dockerfile in $_dockerfile_list; do
        _image_base_tag="$(sed \
            --expression='s|^FROM '"$docker_debian_repo"':\([^ ]\+\)\s.\+|\1|p' \
            --silent \
            "$_dockerfile"
        )"
        _gcc_version_major="$(printf '%s' "$_dockerfile" | sed \
            --expression='s/.\+gcc-slim-\([0-9]\+\).\+/\1/p' \
            --silent \
        )"
        _gcc_version_full="$(printf '%s' "$_data" | sed \
            --expression='s/.\+"version":"\('"$_gcc_version_major"'[^"]\+\)".\+/\1/p' \
            --silent \
        )"
        _gcc_revision="$(printf '%s' "$_data" | sed \
            --expression='s/.\+'"$_gcc_version_full"'.\+"revision":"\([^"]\+\).\+/\1/p' \
            --silent \
        )"
        # https://hub.docker.com/ doesn't accept to send only a range of data
        _image_base_digest="$( \
            curl \
                --location \
                --silent \
                --url "$docker_api_url_debian_tags/$_image_base_tag" \
            | sed \
                --expression='s/[^}]\+}/&\n/g' \
                --expression='s/.\+"architecture"\s*:\s*"amd64"[^\n]\+"digest"\s*:\s*"\([^"]\+\)".\+/\1/p' \
                --silent \
        )"
        _image_base_name="$docker_debian_repo:$_image_base_tag@$_image_base_digest"
        # Tag format doesn't allow `+` and `~`
        # See: https://github.com/distribution/distribution/blob/main/reference/reference.go#L18
        # Replace `+` with `p` and `~` with `t`
        _tag="$(printf '%s' "$_gcc_version_full" | sed \
            --expression='s/+/p/p' \
            --expression='s/~/t/p' \
            --silent
        )"
        if [ -z "$_tag" ]; then
            _tag="$_gcc_version_full"
        fi
        printf '%s\n' "$_tag"
        podman build . \
            --tag "sequpt/gcc-slim:$_gcc_version_major" \
            --tag "sequpt/gcc-slim:$_tag" \
            --file "$_dockerfile" \
            --label "org.opencontainers.image.authors=sequpt" \
            --label "org.opencontainers.image.base.name=$_image_base_name" \
            --label "org.opencontainers.image.created=$(date --iso-8601=seconds --utc)" \
            --label "org.opencontainers.image.description=The GNU Compiler Collection" \
            --label "org.opencontainers.image.documentation=$_url" \
            --label "org.opencontainers.image.licenses=" \
            --label "org.opencontainers.image.ref.name=$_gcc_version_major" \
            --label "org.opencontainers.image.revision=$_gcc_revision" \
            --label "org.opencontainers.image.source=$_url" \
            --label "org.opencontainers.image.title=GCC" \
            --label "org.opencontainers.image.url=$_url" \
            --label "org.opencontainers.image.vendor=sequpt" \
            --label "org.opencontainers.image.version=$_gcc_version_full"
    done
}
#-------------------------------------------------------------------------------
# main()
#-------------------------------------------------------------------------------
main() {
    suites_path='./suites'
    versions_path='./versions'
    update_suites "$suites_path"
    suite_data="$(cat "$suites_path")"
    update_versions "$versions_path" "$suite_data"
    versions_data="$(cat "$versions_path")"
    generate_dockerfiles "$versions_data"
    build_images "$versions_data"
}
main "$@"
