#!/usr/bin/env bash

#
# Copyright (c) 2014-present, The osquery authors
#
# This source code is licensed as defined by the LICENSE file found in the
# root directory of this source tree.
#
# SPDX-License-Identifier: (Apache-2.0 OR GPL-2.0-only)
#

main() {
  if [[ $# != 3 ]] ; then
    printf "Usage:\n\t$0 <source> <destination> <architecure>\n"
    return 1
  fi

  local source="$1"
  local destination="$(realpath $2)"
  local architecture="$3"

  local python_architecture
  if [ "$architecture" = "x86_64" ]; then
    python_architecture="x64"
  else
    python_architecture="$architecture"
  fi

  printf "Source path: ${source}\n"
  printf "Destination path: ${destination}\n"
  printf "Architecture: ${architecture}\n\n"

  ( cd "${source}" && copy_files "${destination}" ) || return 1
  patch_make_files "${destination}" "${python_architecture}" || return 1
  patch_ctest_files "$(realpath ${source})" "${destination}" "${python_architecture}" || return 1

  printf "Generating the launcher..\n"
  local launcher_path="${destination}/run.sh"

  printf '#!/usr/bin/env bash\n\n' > "${launcher_path}"
  printf 'export RUNNER_ROOT_FOLDER="$(pwd)"\n\n' >> "${launcher_path}"
  printf 'ctest --build-nocmake -V\n' >> "${launcher_path}"
  chmod 755 "${launcher_path}" || return 1

  printf "Generating the archive..\n\n"

  local dest_folder_name="$(basename ${destination})"
  local archive_parent="$(dirname ${destination})"
  ( cd "${archive_parent}" && tar -pcvzf "${dest_folder_name}.tar.gz" "${dest_folder_name}" ) || return 1

  printf "Archive path: ${destination}.tar.gz\n"
  return 0
}

copy_files() {
  if [[ $# != 1 ]] ; then
    printf "Usage:\n\t$0 <destination>\n"
    return 1
  fi

  local destination="$1"

  printf "Copying...\n\n"

  find . -type f \( -name '*-test' -o -iname '*ctest*' \) | grep -v 'openssl-prefix' | while read file_path ; do
    folder_path="$(dirname ${file_path})"
    dest_folder_path="${destination}/${folder_path}"

    printf "  ${file_path}\n"

    mkdir -p "${dest_folder_path}" || return 1
    cp -p "${file_path}" "${dest_folder_path}" || return 1
  done

  cp -rp "test_configs" "${destination}" || return 1

  mkdir -p "${destination}/tools" || return 1
  cp -rp "tools/tests" "${destination}/tools" || return 1

  cp -r "python_path" "${destination}" || return 1

  mkdir -p "${destination}/osquery" || return 1
  cp "osquery/osqueryd" "${destination}/osquery" || return 1
  cp "osquery/osqueryi" "${destination}/osquery" || return 1

  printf "\n"
  return 0
}

patch_make_files() {
  if [[ $# != 2 ]] ; then
    printf "Usage:\n\t$0 <destination> <python_architecture>\n"
    return 1
  fi

  local destination="$1"
  local python_architecture="$2"

  printf "Patching the Make files...\n\n"

  local cmake_path="$(which cmake)"
  if [[ $? != 0 ]] ; then
    printf "Failed to locate the cmake binary\n"
    return 1
  fi

  which gsed > /dev/null 2>&1
  if [[ $? == 0 ]] ; then
    local sed_binary="gsed"
    local in_place_option="-i"
  else
    local sed_binary="sed"
    local in_place_option="-i ''"
  fi

  find "${destination}" -type f \( -name '*.make' -o -name 'Makefile' -o -name '*.cmake' \) | while read file_path ; do
    printf "  ${file_path}\n"

    ${sed_binary} "s#${cmake_path}#cmake#g" $in_place_option "${file_path}"
    ${sed_binary} "s#Python/\([0-9.]*\)/[^/]*/bin/python3#Python/\1/${python_architecture}/bin/python3#g" $in_place_option "${file_path}"
  done

  return 0
}

patch_ctest_files() {
  if [[ $# != 3 ]] ; then
    printf "Usage:\n\t$0 <source> <destination> <python_architecture>\n"
    return 1
  fi

  local source="$1"
  local destination="$2"
  local python_architecture="$3"

  printf "Patching the CTest files...\n\n"

  which gsed > /dev/null 2>&1
  if [[ $? == 0 ]] ; then
    local sed_binary="gsed"
    local in_place_option="-i"
  else
    local sed_binary="sed"
    local in_place_option="-i ''"
  fi

  printf "  sed binary: '${sed_binary}'\n\n"

  find "${destination}" -type f -name '*.cmake' | while read file_path ; do
    printf "  ${file_path}\n"

    ${sed_binary} "s=${source}=\$ENV{RUNNER_ROOT_FOLDER}=g" $in_place_option "${file_path}"
    ${sed_binary} 's#TEST_CONF_FILES_DIR=${source}/test_configs#TEST_CONF_FILES_DIR=$ENV{RUNNER_ROOT_FOLDER}/test_configs#g' $in_place_option "${file_path}"
    ${sed_binary} 's#TEST_HELPER_SCRIPTS_DIR=${source}/tools/tests#TEST_HELPER_SCRIPTS_DIR=$ENV{RUNNER_ROOT_FOLDER}/tools/tests#g' $in_place_option "${file_path}"
    ${sed_binary} "s#Python/\([0-9.]*\)/[^/]*/bin/python3#Python/\1/${python_architecture}/bin/python3#g" $in_place_option "${file_path}"
  done

  printf "\n"
  return 0
}

main $@
exit $?
