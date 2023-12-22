
# declare -A DAG
# declare CURRENT_TARGET

# DAG["build"]="dependency1,dependency2->output1,output5 dependency3,dependency5->output2"
# DAG["run"]="dependency6"

# add_argument "output-name" "string" "the filename of the generated output"
# DAG["build"]="%%{input-names}.c,%%{input-names}.h->%%{input-names}.o %%{input-names}->%{output-name}"
# %%{} is an eval that uses the environment
# %{} is an eval that uses an argument name for the currently-scoped target

function provides () {
    return
}

function consumes () {
    return
}

function export_dag () {
    local target="$1"
    local dotfile="$2"

    echo "digraph G {" > "${dotfile}"
    for target in "${!DAG[@]}"; do
        echo "  subgraph cluster_${target} {" >> "${dotfile}"
        echo "    label = \"${target}\";" >> "${dotfile}"
        IFS=' ' read -ra transformations <<< "${DAG[$target]}"
        for transformation in "${transformations[@]}"; do
            IFS=':' read -ra parts <<< "${transformation}"
            transformation_name="${parts[0]}"
            echo "    ${transformation_name} [shape=box];" >> "${dotfile}"
            IFS=' ' read -ra dependencies <<< "$(echo ${parts[1]} | tr '->' ' ')"
            for ((i=0; i<${#dependencies[@]}; i+=2)); do
                echo "    ${dependencies[i]} -> ${transformation_name} [label=\"${dependencies[i+1]}\"];" >> "${dotfile}"
            done
        done
        echo "  }" >> "${dotfile}"
    done
    echo "}" >> "${dotfile}"
}

# export_dag target1 target1.dot
