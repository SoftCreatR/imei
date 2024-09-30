#!/bin/bash
install_svtav1() {
  cd "$WORK_DIR" || exit 1
  if {
    echo -ne ' Building svt-av1              [..]\r'

    if [ "$(version "$CMAKE_VERSION")" -lt "$(version 3.16)" ]; then
      echo -ne " Building libsvtav1              [${CYELLOW}SKIPPED (CMAKE version $CMAKE_VERSION not sufficient)${CEND}]\\r"
      echo ""

      return
    fi

    if [ -n "$AV1ENC" ] && [ -z "$SKIP_LIBHEIF" ]; then
      if [ -z "$FORCE" ] && [ -n "$INSTALLED_SVT_VER" ] && [ "$(version "$INSTALLED_SVT_VER")" -ge "$(version "$SVT_VER")" ]; then
        echo -ne " Building svt-av1              [${CYELLOW}SKIPPED${CEND}]\\r"
        echo ""

        return
      fi
    else
      echo -ne " Building svt-av1              [${CYELLOW}SKIPPED${CEND}]\\r"
      echo ""

      return
    fi

    {
      if [ -n "$SVT_VER" ]; then
        httpGet "$GL_FILE_BASE/AOMediaCodec/SVT-AV1/-/archive/v${SVT_VER}/SVT-AV1-v${SVT_VER}.tar.gz" > "SVT-AV1-v${SVT_VER}.tar.gz"

        if [ -n "$SVT_HASH" ]; then
          if [ "$(sha1sum "svt-av1-$SVT_VER.tar.gz" | cut -b-40)" != "$SVT_HASH" ]; then
            echo -ne " Building svt-av1              [${CRED}FAILURE${CEND}]\\r"
            echo ""
            echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
            echo ""
          fi
        fi

        # see https://github.com/SoftCreatR/imei/issues/9
        CMAKE_FLAGS=(-G"Unix Makefiles" -DCMAKE_BUILD_TYPE=Release)

        # Should we keep this?
        #if [[ "${OS_DISTRO,,}" == *"raspbian"* ]]; then
        #  CMAKE_FLAGS+=(-DCMAKE_C_FLAGS="-mfloat-abi=hard -march=armv7-a -marm -mfpu=neon")
        #fi

        tar -xf "SVT-AV1-v${SVT_VER}.tar.gz" &&
          cd "$WORK_DIR/SVT-AV1-v${SVT_VER}/Build" &&
          cmake .. "${CMAKE_FLAGS[@]}" &&
          make -j "$(nproc)"

        if [ -n "$CHECKINSTALL" ]; then
          echo "Scalable Video Technology for AV1 (IMEI v$INSTALLER_VER)" >>description-pak &&
            checkinstall \
              --default \
              --nodoc \
              --pkgname="imei-libsvtav1" \
              --pkglicense="BSD-3-clause" \
              --pkgversion="$SVT_VER" \
              --pkgrelease="imei$INSTALLER_VER" \
              --pakdir="$BUILD_DIR" \
              --provides="libsvtav1 \(= $SVT_VER\)" \
              --fstrans="${FSTRANS:-"no"}" \
              --backup=no \
              --deldoc=yes \
              --deldesc=yes \
              --delspec=yes \
              --install=yes \
              make -j "$(nproc)" install
        else
          make -j "$(nproc)" install
        fi

        ldconfig "$LIB_DIR"
      fi
    } >>"$LOG_FILE" 2>&1
  }; then
    export UPDATE_LIBHEIF="yes"

    echo -ne " Building svt-av1              [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -ne " Building svt-av1              [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}
