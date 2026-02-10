checkImage () {
    local USE_QUAY="true"
    local QUIET=1

    checkImage_result=""
    local imageAndSHA="$1"
    imageAndSHA=${imageAndSHA/registry.redhat.io\/rhdh/quay.io\/rhdh}
    imageAndSHA=${imageAndSHA%%@*}
    imageOnly=${imageAndSHA%%:*}
    if [[ $QUIET -eq 0 ]]; then echo "For $imageAndSHA"; fi

    # echo "[DEBUG] Got image = $image"
    # shellcheck disable=SC2086
    image_version=$(skopeo inspect docker://${imageAndSHA} 2>/dev/null | jq -r '.Labels.version')
    # shellcheck disable=SC2086
    image_release=$(skopeo inspect docker://${imageAndSHA} 2>/dev/null | jq -r '.Labels.release')

    # echo "[DEBUG] For $imageOnly, got $image_version - $image_release"
    if [[ $image_version ]] && [[ $image_release ]]; then
        container=${imageOnly}:${image_version}-${image_release}
        digest="$(skopeo inspect "docker://${container}" 2>/dev/null | jq -r '.Digest' 2>/dev/null )"
        if [[ $digest ]]; then
          container="${container%:*}@$digest"
          if [[ $QUIET -eq 0 ]]; then echo "Got $container for ${imageOnly}:${image_version}-${image_release}"; else echo "       * $container (${imageOnly}:${image_version}-${image_release})"; fi
        else
          # try previous image
          # shellcheck disable=SC2086
          image_release=$(int $image_release)
          (( image_release = image_release-1 ))
          container=${imageOnly}:${image_version}-${image_release}
          digest="$(skopeo inspect "docker://${container}" 2>/dev/null | jq -r '.Digest' 2>/dev/null )"
          if [[ $digest ]]; then
            container="${container%:*}@$digest"
            if [[ $QUIET -eq 0 ]]; then echo "Got $container for ${imageOnly}:${image_version}-${image_release}"; else echo "       * $container (${imageOnly}:${image_version}-${image_release})"; fi
          else
            # no digest, so just use :tag
            container=${imageOnly}:${image_version}
            digest="$(skopeo inspect "docker://${container}" 2>/dev/null | jq -r '.Digest' 2>/dev/null )"
            if [[ $digest ]]; then
              container="${container%:*}@$digest"
            fi
            if [[ $QUIET -eq 0 ]]; then echo "Got $container for ${imageOnly}:${image_version}"; else echo "       * $container (${imageOnly}:${image_version})"; fi
          fi
        fi
        checkImage_result="$container"
    else
        if [[ ${imageAndSHA} == "quay.io/"* ]];then
            echo "Not found: $imageAndSHA"
        elif [[ $USE_QUAY != "true" ]]; then
            echo "Not found; try --quay or -y flag to check same image on quay.io registry"
        fi
        if [[ "$USE_QUAY" == "true" ]]; then
            checkImage_result="NONE"
        fi
    fi
    # skopeo inspect docker://${container} | jq -r .Digest # note, this might be different from the input SHA, but still equivalent
}


declare -A digest_mapping


          yml=manifests/rhdh-plugin-deps_v1_configmap.yaml
          echo -e "\n[INFO] Transform $bundle_dir/$yml ..."
          sed -i $yml -r \
              -e "s@quay.io/fedora/postgresql-15:.+@registry.redhat.io/rhel9/postgresql-15:latest@g"
          for d in registry.redhat.io/rhel9/postgresql-15:latest; do
            if [[ ! ${digest_mapping[$d]} ]]; then
              checkImage "$d"
              echo "       + Got $checkImage_result for $d"
              if [[ "$checkImage_result" != "NONE" ]]; then
                digest_mapping["${d}"]="${checkImage_result}"
              fi
            else
              checkImage_result="${digest_mapping[$d]}"
            fi
            if [[ "$checkImage_result" != "NONE" ]]; then
              sed -i $yml -r -e "s|$d|$checkImage_result|g"
            fi
          done






          #sed -i $yml -r -e "s@quay.io/rhdh/@registry.redhat.io/rhdh/@g"
          # debugging: show contents after transformation
          # grep "image:" $yml
