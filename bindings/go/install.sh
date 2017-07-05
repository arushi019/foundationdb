#!/bin/bash -eu
#
# install.sh
#
# Installs the FoundationDB Go bindings for a client. This will download
# the repository from the remote repo either into the go directory
# with the appropriate semantic version. It will then build a few
# generated files that need to be present for the go build to work.
# At the end, it has some advice for flags to modify within your
# go environment so that other packages may successfully use this
# library.
#

DESTDIR="${DESTDIR:-}"
FDBVER="${FDBVER:-5.0.1}"
REMOTE="${REMOTE:-github.geo.apple.com}"
FDBREPO="${FDBREPO:-cie/foundation}"

status=0

platform=$(uname)
if [[ "${platform}" == "Darwin" ]] ; then
    FDBLIBDIR="${FDBLIBDIR:-/usr/local/lib}"
    libfdbc="libfdb_c.dylib"
elif [[ "${platform}" == "Linux" ]] ; then
    FDBLIBDIR="${FDBLIBDIR:-/usr/lib}"
    libfdbc="libfdb_c.so"
else
    echo "Unsupported platform ${platform}".
    echo "At the moment, only macOS and Linux are supported by this script."
    let status="${status} + 1"
fi

filedir=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
destdir=""

function printUsage() {
    echo "Usage: install.sh <cmd>"
    echo
    echo "cmd: One of the commands to run. The options are:"
    echo "     install         Download the FDB go bindings and install them"
    echo "     localinstall    Install a into the go path a local copy of the repo"
    echo "     download        Download but do not prepare the FoundationDB bindings"
    echo "     help            Print this help message and then quit"
    echo
    echo "Command Line Options:"
    echo "     --fdbver <version>    FoundationDB semantic version (default is ${FDBVER})"
    echo "     -d/--dest-dir <dest>  Local location for the repo (default is to place in go path)"
    echo
    echo "Environment Variable Options:"
    echo "     REMOTE          Remote repository to download from (currently ${REMOTE})"
    echo "     FDBREPO         Repository of FoundationDB library to download (currently ${FDBREPO})"
    echo "     FDBLIBDIR       Directory within which should be the FoundationDB c library (currently ${FDBLIBDIR})"
}

function parseArgs() {
    local status=0

    if [[ "${#}" -lt 0 ]] ; then
        printUsage
        let status="${status} + 1"
    else
        operation="${1}"
        shift
        if [[ "${operation}" != "install" ]] && [[ "${operation}" != "localinstall" ]] && [[ "${operation}" != "download" ]] && [[ "${operation}" != "help" ]] ; then
            echo "Unknown command: ${operation}"
            printUsage
            let status="${status} + 1"
        fi
    fi

    while [[ "${#}" -gt 0 ]] && [[ "${status}" -eq 0 ]] ; do
        local key="${1}"
        case "${key}" in
            --fdbver)
            if [[ "${#}" -lt 2 ]] ; then
                echo "No version specified with --fdbver flag"
                printUsage
                let status="${status} + 1"
            else
                FDBVER="${2}"
            fi
            shift
            ;;

            -d|--dest-dir)
            if [[ "${#}" -lt 2 ]] ; then
                echo "No destination specified with ${key} flag"
                printUsage
                let status="${status} + 1"
            else
                destdir="${2}"
            fi
            shift
            ;;

            *)
            echo "Unrecognized argument ${key}"
            printUsage
            let status="${status} + 1"
        esac
        shift
    done

    return "${status}"
}

function checkBin() {
    if [[ "${#}" -lt 1 ]] ; then
        echo "Usage: checkBin <binary>"
        return 1
    else
        if [[ -n $(which "${1}") ]] ; then
            return 0
        else
            return 1
        fi
    fi
}

if [[ "${status}" -gt 0 ]] ; then
    # We have already failed.
    :
elif [[ "${#}" -lt 1 ]] ; then
    printUsage
else
    required_bins=( 'go' 'git' 'make' 'mono' )

    missing_bins=()
    for bin in "${required_bins[@]}" ; do
        if ! checkBin "${bin}" ; then
            missing_bins+=("${bin}")
            let status="${status} + 1"
        fi
    done

    if [[ "${status}" -gt 0 ]] ; then
        echo "Missing binaries: ${missing_bins[*]}"
    elif ! parseArgs ${@} ; then
        let status="${status} + 1"
    elif [[ "${operation}" == "help" ]] ; then
        printUsage
    else
        # Add go-specific environment variables.
        eval $(go env)

        golibdir=$(dirname "${GOPATH}/src/${REMOTE}/${FDBREPO}")
        if [[ -z "${destdir}" ]] ; then
            if [[ "${operation}" == "localinstall" ]] ; then
                # Assume its the local directory.
                destdir=$(cd "${filedir}/../../.." && pwd)
            else
                destdir="${golibdir}"
            fi
        fi

        if [[ ! -d "${destdir}" ]] ; then
            cmd=( 'mkdir' '-p' "${destdir}" )
            echo "${cmd[*]}"
            if ! "${cmd[@]}" ; then
                let status="${status} + 1"
                echo "Could not create destination directory ${destdir}."
            fi
        fi

        # Step 1: Make sure repository is present.

        if [[ "${status}" -eq 0 ]] ; then
            destdir=$( cd "${destdir}" && pwd ) # Get absolute path of destination dir.
            fdbdir="${destdir}/foundation"

            if [[ ! -d "${destdir}" ]] ; then
                cmd=("mkdir" "-p" "${destdir}")
                echo "${cmd[*]}"
                if ! "${cmd[@]}" ; then
                    echo "Could not create destination directory ${destdir}."
                    let status="${status} + 1"
                fi
            fi
        fi

        if [[ "${operation}" == "localinstall" ]] ; then
            # No download occurs in this case.
            :
        else
            if [[ -d "${fdbdir}" ]] ; then
                echo "Directory ${fdbdir} already exists ; checking out appropriate tag"
                cmd1=( 'git' '-C' "${fdbdir}" 'fetch' 'origin' )
                cmd2=( 'git' '-C' "${fdbdir}" 'checkout' "release-${FDBVER}" )

                if ! echo "${cmd1[*]}" || ! "${cmd1[@]}" ; then
                    let status="${status} + 1"
                    echo "Could not pull latest changes from origin"
                elif ! echo "${cmd2[*]}" ||  ! "${cmd2[@]}" ; then
                    let status="${status} + 1"
                    echo "Could not checkout tag release-${FDBVER}."
                fi
            else
                echo "Downloading foundation repository into ${destdir}:"
                cmd=( 'git' '-C' "${destdir}" 'clone' '--branch' "release-${FDBVER}" "git@${REMOTE}:${FDBREPO}.git" )

                echo "${cmd[*]}"
                if ! "${cmd[@]}" ; then
                    let status="${status} + 1"
                    echo "Could not download repository."
                fi
            fi
        fi

        # Step 2: Build generated things.

        if [[ "${operation}" == "download" ]] ; then
            # The generated files are not created under a strict download.
            :
        elif [[ "${status}" -eq 0 ]] ; then
            echo "Building generated files."
            cmd=( 'make' '-C' "${fdbdir}" 'bindings/c/foundationdb/fdb_c_options.g.h' )

            echo "${cmd[*]}"
            if ! "${cmd[@]}" ; then
                let status="${status} + 1"
                echo "Could not generate required c header"
            else
                infile="${fdbdir}/fdbclient/vexillographer/fdb.options"
                outfile="${fdbdir}/bindings/go/src/fdb/generated.go"
                cmd=( 'go' 'run' "${fdbdir}/bindings/go/src/_util/translate_fdb_options.go" )
                echo "${cmd[*]} < ${infile} > ${outfile}"
                if ! "${cmd[@]}" < "${infile}" > "${outfile}" ; then
                    let status="${status} + 1"
                    echo "Could not generate generated go file."
                fi
            fi
        fi

        # Step 3: Add to go path.

        if [[ "${operation}" == "download" ]] ; then
            # The files are not moved under a strict download.
            :
        elif [[ "${status}" -eq 0 ]] ; then
            linkpath="${GOPATH}/src/${REMOTE}/${FDBREPO}"
            if [[ "${linkpath}" == "${fdbdir}" ]] ; then
                # Downloaded directly into go path. Skip making the link.
                :
            elif [[ -e "${linkpath}" ]] ; then
                echo "Warning: link path (${linkpath}) already exists. Leaving in place."
            else
                dirpath=$(dirname "${linkpath}")
                if [[ ! -d "${dirpath}" ]] ; then
                    cmd=( 'mkdir' '-p' "${dirpath}" )
                    echo "${cmd[*]}"
                    if ! "${cmd[@]}" ; then
                        let status="${status} + 1"
                        echo "Could not create directory for link."
                    fi
                fi

                if [[ "${status}" -eq 0 ]] ; then
                    cmd=( 'ln' '-s' "${fdbdir}" "${linkpath}" )
                    echo "${cmd[*]}"
                    if ! "${cmd[@]}" ; then
                        let status="${status} + 1"
                        echo "Could not create link within go path."
                    fi
                fi
            fi
        fi

        # Step 4: Explain CGO flags.

        if [[ "${status}" -eq 0 && ("${operation}" == "localinstall" || "${operation}" == "install" ) ]] ; then
            echo
            echo "The FoundationDB go bindings were successfully installed."
            echo "To build packages which use the go bindings, you will need to"
            echo "set the following environment variables:"
            echo "   CGO_CFLAGS=\"-g -O2 -I${linkpath}/bindings/c\""
            echo "   CGO_LDFLAGS=\"-g -O2 -L${FDBLIBDIR}\""

            if [[ ! -e "${FDBLIBDIR}/${libfdbc}" ]] ; then
                echo
                echo "WARNING: The FoundationDB C library was not found within ${FDBLIBDIR}."
                echo "Your installation may be incomplete."
            fi
        fi
    fi
fi

exit "${status}"
