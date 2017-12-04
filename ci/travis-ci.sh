CCORE_X64_BINARY_PATH=pyclustering/core/x64/linux/ccore.so
CCORE_X86_BINARY_PATH=pyclustering/core/x86/linux/ccore.so


INF_COLOR_CODE='\033[0;32m'
ERR_COLOR_CODE='\033[0;31m'
RST_COLOR_CODE='\033[0m'


print_error() {
    echo $ERR_COLOR_CODE"ERROR: $1"$RST_COLOR_CODE
}


print_info() {
    echo $INF_COLOR_CODE"$1"$RST_COLOR_CODE
}


check_failure() {
    if [ $? -ne 0 ] ; then
        if [ -z $1 ] ; then
            print_error $1
        else
            print_error "Failure exit code is detected."
        fi
        exit 1
    fi
}


build_ccore() {
    if [ "$1" == "x64" ]; then
        make ccore_x64
        check_failure "Building CCORE (x64): FAILURE."
    elif [ "$1" == "x86" ]
        make ccore_x86
        check_failure "Building CCORE (x86): FAILURE."
    else
        print_error "Unknown CCORE platform is specified."
        exit 1
    fi
}


run_build_ccore_job() {
    print_info "CCORE (C++ code building):"
    print_info "- Build CCORE library for x64 platform."
    print_info "- Build CCORE library for x86 platform."

    #install requirement for the job
    print_info "Install requirement for CCORE building."

    sudo apt-get install -qq g++-5
    sudo apt-get install -qq g++-5-multilib
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-5 50

    # show info
    g++ --version
    gcc --version

    # build ccore library
    cd ccore/

    build_ccore x64
    build_ccore x86

    upload_binary x64
    upload_binary x86

    # return back (keep current folder)
    cd ../
}


run_analyse_ccore_job() {
    print_info "ANALYSE CCORE (C/C++ static analysis):"
    print_info "- Code checking using 'cppcheck'."

    # install requirement for the job
    print_info "Install requirement for static analysis of CCORE."

    sudo apt-get install -qq cppcheck

    # analyse source code
    cd ccore/

    make cppcheck
    check_failure "C/C++ static analysis: FAILURE."

    # return back (keep current folder)
    cd ../
}


run_ut_ccore_job() {
    print_info "UT CCORE (C++ code unit-testing of CCORE library):"
    print_info "- Build C++ unit-test project for CCORE library."
    print_info "- Run CCORE library unit-tests."

    # install requirements for the job
    sudo apt-get install -qq g++-5
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-5 50
    sudo update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-5 50

    pip install cpp-coveralls

    # build unit-test project
    cd ccore/

    make ut
    check_failure "Building CCORE unit-tests: FAILURE."

    # run unit-tests and obtain code coverage
    make utrun
    check_failure "CCORE unit-testing status: FAILURE."
    
    # step back to have full path to files in coverage reports
    coveralls --root ../ --build-root . --exclude ccore/tst/ --exclude ccore/tools/ --gcov-options '\-lp'

    # return back (keep current folder)
    cd ../
}


run_valgrind_ccore_job() {
    print_info "VALGRIND CCORE (C++ code valgrind checking):"
    print_info "- Run unit-tests of pyclustering."
    print_info "- Memory leakage detection by valgrind."

    # install requirements for the job
    sudo apt-get install -qq g++-5
    sudo apt-get install -qq valgrind
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-5 50

    # build and run unit-test project under valgrind to check memory leakage
    cd ccore/

    make valgrind
    check_failure "CCORE memory leakage status: FAILURE."

    # return back (keep current folder)
    cd ../
}


run_test_pyclustering_job() {
    print_info "TEST PYCLUSTERING (unit and integration testing):"
    print_info "- Rebuilt CCORE library."
    print_info "- Run unit and integration tests of pyclustering."
    print_info "- Measure code coverage for python code."

    # install requirements for the job
    install_miniconda
    pip install coveralls

    # set path to the tested library
    PYTHONPATH=`pwd`
    export PYTHONPATH=${PYTHONPATH}

    # build ccore library
    build_ccore x64

    # show info
    python --version
    python3 --version

    # run unit and integration tests and obtain coverage results
    coverage run --source=pyclustering --omit='pyclustering/*/tests/*,pyclustering/*/examples/*,pyclustering/tests/*' pyclustering/tests/tests_runner.py
    coveralls
}


run_integration_test_job() {
    print_info "INTEGRATION TESTING ('ccore' <-> 'pyclustering')."
    print_info "- Build CCORE library."
    print_info "- Run integration tests of pyclustering."

    PYTHON_VERSION=$1

    # install requirements for the job
    install_miniconda $PYTHON_VERSION

    # build ccore library
    build_ccore x64

    # run integration tests
    python pyclustering/tests/tests_runner.py --integration
}


run_doxygen_job() {
    print_info "DOXYGEN (documentation generation)."
    print_info "- Generate documentation and check for warnings."


    # install requirements for the job
    print_info "Install requirements for doxygen."

    sudo apt-get install doxygen
    sudo apt-get install graphviz
    sudo apt-get install texlive


    # generate doxygen documentation
    print_info "Generate documentation."

    doxygen docs/doxygen_conf_pyclustering > /dev/null 2> doxygen_problems.txt
    
    problems_amount=$(cat doxygen_problems.txt | wc -l)
    printf "Total amount of doxygen errors and warnings: '%d'\n"  "$problems_amount"
    
    if [ $problems_amount -ne 0 ] ; then
        print_info "List of warnings and errors:"
        cat doxygen_problems.txt
        
        print_error "Building doxygen documentation: FAILURE."
        exit 1
    fi

    print_info "Building doxygen documentation: SUCCESS."
}


install_miniconda() {
    PYTHON_VERSION=3.4
    if [ $# -eq 1 ]; then
        PYTHON_VERSION=$1
    fi

    wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh

    bash miniconda.sh -b -p $HOME/miniconda

    export PATH="$HOME/miniconda/bin:$PATH"
    hash -r

    conda config --set always_yes yes --set changeps1 no
    conda update -q conda

    conda install libgfortran
    conda create -q -n test-environment python=3.4 numpy scipy matplotlib Pillow
    source activate test-environment
}


upload_binary() {
    print_info "Upload binary files to storage."

    BUILD_FOLDER=linux
    BUILD_PLATFORM=$1
    BINARY_FOLDER=$TRAVIS_BUILD_NUMBER

    CCORE_BINARY_PATH=
    if [ "$BUILD_PLATFORM" == "x64" ]; then
        LOCAL_BINARY_PATH=$CCORE_X64_BINARY_PATH
    elif [ "$BUILD_PLATFORM" == "x86" ]; then
        LOCAL_BINARY_PATH=$CCORE_X86_BINARY_PATH
    else
        print_error "Invalid platform is specified '$BUILD_PLATFORM' for uploading."
        exit 1
    fi

    # Create folder for uploaded binary file
    curl -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X PUT https://cloud-api.yandex.net:443/v1/disk/resources?path=$TRAVIS_BRANCH
    curl -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X PUT https://cloud-api.yandex.net:443/v1/disk/resources?path=$TRAVIS_BRANCH%2F$BUILD_FOLDER
    curl -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X PUT https://cloud-api.yandex.net:443/v1/disk/resources?path=$TRAVIS_BRANCH%2F$BUILD_FOLDER%2F$BUILD_PLATFORM
    curl -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X PUT https://cloud-api.yandex.net:443/v1/disk/resources?path=$TRAVIS_BRANCH%2F$BUILD_FOLDER%2F$BUILD_PLATFORM%2F$BINARY_FOLDER

    # Obtain link for uploading
    REMOTE_BINARY_FILEPATH=$TRAVIS_BRANCH%2F$BUILD_FOLDER%2F$BUILD_PLATFORM%2F$BINARY_FOLDER%2Fccore.so
    
    print_info "Upload binary using path '$REMOTE_BINARY_FILEPATH'."

    UPLOAD_LINK=`curl -s -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X GET https://cloud-api.yandex.net:443/v1/disk/resources/upload?path=$REMOTE_BINARY_FILEPATH |\
        python3 -c "import sys, json; print(json.load(sys.stdin)['href'])"`

    curl -H "Authorization: OAuth $YANDEX_DISK_TOKEN" -X PUT $UPLOAD_LINK --upload-file $LOCAL_BINARY_PATH
}


set -e
set -x


case $1 in
    BUILD_CCORE) 
        run_build_ccore_job ;;

    ANALYSE_CCORE)
        run_analyse_ccore_job ;;

    UT_CCORE) 
        run_ut_ccore_job ;;

    VALGRIND_CCORE)
        run_valgrind_ccore_job ;;

    TEST_PYCLUSTERING) 
        run_test_pyclustering_job ;;

    IT_CCORE)
        run_integration_test_job $2 ;;

    DOCUMENTATION)
        run_doxygen_job ;;

    *)
        print_error "Unknown target is specified: '$1'"
        exit 1 ;;
esac
