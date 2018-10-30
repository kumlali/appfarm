#!/bin/bash
# ------------------------------------------------------------------------------
# WARNING: This file might be overriden while deployment.
# ------------------------------------------------------------------------------
# Manages single instance of the application, e.g., Springboot, Dropwizard.
#
# Note: Domain might have multiple nodes and each node might have multiple 
# instances.
# ------------------------------------------------------------------------------



# ------------------------------------------------------------------------------
# Moves the instance's log files to ${CONF_APP_HOME}/logs/archive/${INSTANCE_NAME}/YYYYMMDD/HHMM 
# directory, if it is not running.
# ------------------------------------------------------------------------------
archiveLogs () {
  
  if [[ `isAlive` = "true" ]]; then
    log "The instance is running. Logs cannot be archived while the instance is running."
    exit 1
  fi

  local current_date=`date +"%Y%m%d"`
  local current_time=`date +"%H%M"`
  local archive_dir=${CONF_APP_HOME}/logs/archive/${INSTANCE_NAME}/${current_date}/${current_time}
  mkdir -m 755 -p ${archive_dir}

  local instance_logs_dir=${INSTANCE_HOME}/logs
  if [ ! -d ${instance_logs_dir} ]; then
    log "'${instance_logs_dir}' directory does not exist. Installation of '${INSTANCE_HOME}' might not be completed."
    exit 1
  fi

  local file_count=$(ls -1 ${instance_logs_dir}/* 2>/dev/null | wc -l)
  if [ ${file_count} != 0 ]; then
    log "Archiving log files under '${instance_logs_dir}' to '${archive_dir}' ..."

    # Move all the files (not directories) under ${INSTANCE_HOME}/logs to archive
    # directory.
    find ${instance_logs_dir}/* -maxdepth 1 -type f -exec mv {} ${archive_dir} \; 2>/dev/null

    # Grant 755 to archived log files. This is especially necessary for 
    # heap dump (*.hprof) files.
    chmod -R 755 ${archive_dir}

    log "Log files under '${instance_logs_dir}' have been archived to '${archive_dir}'."

  fi

}


# ------------------------------------------------------------------------------
# Returns process id of the instance.
# ------------------------------------------------------------------------------
getProcessId () {

  local process_id=`ps -eF | grep instanceName=${INSTANCE_NAME} | grep -vw grep | awk '{print $2}'`
  echo "$process_id"

}


printEnvironmentVariables () {

  echo "----------------------------------------------------------------"
  echo "Configuration"
  echo "----------------------------------------------------------------"
  echo "CONF_APP_ARGS                :"
  printArguments "${CONF_APP_ARGS}"
  echo "CONF_APP_NAME                : ${CONF_APP_NAME}"
  echo "CONF_APP_HOME                : ${CONF_APP_HOME}"
  echo "CONF_BASE_PORT               : ${CONF_BASE_PORT}"
  echo "CONF_DOMAIN_NAME             : ${CONF_DOMAIN_NAME}"
  echo "CONF_JAVA_HOME               : ${CONF_JAVA_HOME}"
  echo "CONF_JAVA_OPTS               :"
  printArguments "${CONF_JAVA_OPTS}"
  echo "CONF_NODE_INSTANCES          :"
  printNodeAndInstances
  echo "CONF_STARTUP_TIMEOUT_SECONDS : ${CONF_STARTUP_TIMEOUT_SECONDS}"
  echo "CONF_WAIT_INTERVAL_SECONDS   : ${CONF_WAIT_INTERVAL_SECONDS}"
  echo "CONF_SERIAL_DOMAIN_OPERATI...: ${CONF_SERIAL_DOMAIN_OPERATIONS_WAIT_INTERVAL_SECONDS}"
  echo "INSTANCE_HOME                : ${INSTANCE_HOME}"
  echo "INSTANCE_NAME                : ${INSTANCE_NAME}"
  echo "NODE_NAME                    : ${NODE_NAME}"
  echo "PATH                         : ${PATH}"
  echo "----------------------------------------------------------------"

}


# ------------------------------------------------------------------------------
# Returns 'true' if the instance is running and 'false' otherwise.
# ------------------------------------------------------------------------------
isAlive () {

  if [[ `getProcessId` != "" ]]; then
    echo "true"
  else
    echo "false"
  fi 

}


# ------------------------------------------------------------------------------
# Logs status of the instance (running or not).
# ------------------------------------------------------------------------------
status () {

  log "${INSTANCE_NAME} - Running: `isAlive`"

}


# ------------------------------------------------------------------------------
# Deletes the instance's log files if it is not running.
# ------------------------------------------------------------------------------
deleteLogs () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance is running. Logs cannot be deleted while it is running."
    exit 1
  fi

  rm -v ${INSTANCE_HOME}/logs/*.* 2>/dev/null

}


# ------------------------------------------------------------------------------
# Archives the instance's logs, then starts it.
#
# It neither blocks nor checks for failures while the instance is starting up.
# ------------------------------------------------------------------------------
start () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance is already running. This step (starting instance) will be skipped."
    exit 1
  fi

  if [ ! -d ${INSTANCE_HOME} ]; then
    log "The instance does not exist at '${INSTANCE_HOME}' directory. \
         \nYou can create it by issuing './instance.sh ${INSTANCE_NAME} create' command."
    exit 1
  else
    archiveLogs
  fi

  local log_file=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log

  printEnvironmentVariables > $log_file

  nohup ${CONF_JAVA_HOME}/bin/java ${CONF_JAVA_OPTS} \
    -jar ${INSTANCE_HOME}/lib/${CONF_APP_NAME}*.jar \
    ${CONF_APP_ARGS} >> $log_file 2>&1 &

  log "The instance is starting..."

}


# ------------------------------------------------------------------------------
# Fails with error message and exits if it finds out CONF_STARTUP_FAILURE_MSG 
# message in instance's log file.
# ------------------------------------------------------------------------------
failOnError () {

  local log_file=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log
  local error_lines=$(sed -n '/'"${CONF_STARTUP_FAILURE_MSG}"'/,$p' ${log_file} | head -100)
  if [ -n "${error_lines}" ]; then
    log "\n----------------------------------------------------------------------\
         \nERROR\
         \n----------------------------------------------------------------------\
         \n${error_lines}"
    stop
    exit 1
  fi

}


# ------------------------------------------------------------------------------
# Archives the instance's logs, then starts it. It blocks until the instance 
# has been started successfully or an error occurs:
#  * if there is CONF_STARTUP_FAILURE_MSG in log file OR
#  * if CONF_STARTUP_TIMEOUT_SECONDS is exceeded.
# ------------------------------------------------------------------------------
startVerify () {

  start

  local log_file=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log  

  local elapsed_time=0
  
  while [ $(grep -c "${CONF_STARTUP_SUCCESS_MSG}" ${log_file}) = 0 ] && \
        [ ${elapsed_time} -lt ${CONF_STARTUP_TIMEOUT_SECONDS} ] ; do
    sleep ${CONF_WAIT_INTERVAL_SECONDS}
    local elapsed_time=$(expr ${elapsed_time} + ${CONF_WAIT_INTERVAL_SECONDS})
    log "The instance has been starting for $elapsed_time seconds. Please wait..."
    failOnError
  done

  if [ ${elapsed_time} -ge ${CONF_STARTUP_TIMEOUT_SECONDS} ] ; then
    log "\n----------------------------------------------------------------------\
         \nERROR\
         \n----------------------------------------------------------------------\
         \nStarting operation is canceled since expected startup time\
         \n(${CONF_STARTUP_TIMEOUT_SECONDS} sec) has been exceeded.\
         \n\nPlease check the logs."
    stop
    exit 1
  else
    log "The instance has been started."
  fi

}


# ------------------------------------------------------------------------------
# Stops the instance. Process is killed if it does not stop in 
# CONF_SHUTDOWN_TIMEOUT_SECONDS seconds.
# ------------------------------------------------------------------------------ 
stop () {
  
  if [[ `isAlive` = "false" ]]; then
    log "The instance is not running. This step (stopping the instance) will be skipped."
    return 0
  fi

  local log_file=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log

  logToConsoleAndFile "The instance is stopping..." ${log_file}

  local process_id=$(getProcessId)

  kill -SIGKILL ${process_id} # kill -9 ...  

  logToConsoleAndFile "The instance has been stopped by killing process $process_id." ${log_file}

}


# ------------------------------------------------------------------------------
# Stops and then starts the instance.
# ------------------------------------------------------------------------------
restart () {

  stop
  start

}


# ------------------------------------------------------------------------------
# Stops and then starts the instance. It blocks until the instance has been 
# started successfully or an error occurs:
#  * if CONF_STARTUP_FAILURE_MSG is found in log file OR
#  * if CONF_STARTUP_TIMEOUT_SECONDS is exceeded.
# ------------------------------------------------------------------------------
restartVerify () {

  stop
  startVerify

}


# ------------------------------------------------------------------------------
# Opens the instance's log file with 'less' command.
# ------------------------------------------------------------------------------
showLog () {

  less ${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log

}


# ------------------------------------------------------------------------------
# Follows instance's log file. Ctrl+C can be used to exit.
# ------------------------------------------------------------------------------
tailLog () {
  
  tail -f ${INSTANCE_HOME}/logs/${INSTANCE_NAME}.log
  
}


# ------------------------------------------------------------------------------
# Takes thread dump from instance's JVM.
# ------------------------------------------------------------------------------
takeThreadDump () {
  
  local process_id=`getProcessId`
  if [[ $process_id != "" ]]; then
    kill -SIGQUIT $process_id # kill -3 ...
    log "Thread dump file has been created in '${INSTANCE_HOME}/logs' directory."
  else
    echo "Thread dump could not be generated as the instance is not running."
  fi  

}


# ------------------------------------------------------------------------------
# Starts to record memory usage data of the instance to 
# ${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.log
#  
# When IBM JDK is used, Garbage Collection and Memory Visualizer (GCMV) can
# load these data to view and analyze the native memory usage. For more
# information please see https://goo.gl/Mw63D9.
# ------------------------------------------------------------------------------
startMemUsageRecording () {

  local process_id=`getProcessId`
  logFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.log

  nohup ${CONF_APP_HOME}/bin/memusage.sh $process_id memUsageId=$process_id >> $logFile 2>&1 &

  log "Recording of memory usage data has been started. See $logFile file."

}


# ------------------------------------------------------------------------------
# Stops to record memory usage data of the instance.
# ------------------------------------------------------------------------------
stopMemUsageRecording () {

  local process_id=`getProcessId`
  logFile=${INSTANCE_HOME}/logs/${INSTANCE_NAME}.memusage.log

  local mem_usage_process_id=`ps -eF | grep memUsageId=${process_id} | grep -vw grep | awk '{print $2}'`
  kill -9 $mem_usage_process_id

  log "Recording of memory usage data has been stopped. See $logFile file."

}


# ------------------------------------------------------------------------------
# Deploys 'app.zip', if the instance is not running.
#
# 'app.zip' contains application's jar file.
#
#  Old application file, if present, is overridden by the new one.
# ------------------------------------------------------------------------------
deploy () {

  if [[ `isAlive` = "true" ]]; then
    log "Deployment cannot be done while the instance is running."
    exit 1
  fi

  local app_pack=${CONF_APP_HOME}/deploy/latest/app.zip
  if [ ! -f "${app_pack}" ]; then
    log "${app_pack} does not exist. Deployment has been canceled."
    exit 1
  fi

  log "Starting to deploy applications in '${app_pack}'..."

  # Handle each jar file in 'app.zip independently'
  for i in `unzip -Z -1 ${app_pack} | grep .jar`
  do
    app_file=${i}
    app_file_name="${app_file%.*}"
    app_file_ext="${app_file##*.}"

    log "Starting to deploy '${app_file}' ..."

    # Remove deployed application if exists.
    rm -f ${INSTANCE_HOME}/lib/${app_file}

    # Deploy application's jar file. It overrides the old one if exists.
    unzip -oj "${app_pack}" "${app_file}" -d "${INSTANCE_HOME}/lib"

    log "'${app_file}' has been deployed."
  done

  log "Applications in '${app_pack}' have been deployed."

}


# ------------------------------------------------------------------------------
# Creates (but does not start) an instance on the current node, if it does not 
# already exist on any nodes and its name conforms to ${CONF_APP_NAME}<number> 
# pattern. (e.g. myapp01, myapp17, etc.)
#
# WARNING: After the instance has been created, its name must be added to 
#          'farm.conf' file on all the nodes. Instance components must be 
#          deployed before starting the instance, as well.
# ------------------------------------------------------------------------------
create () {

  if [[ ${INSTANCE_NAME} == ${CONF_APP_NAME}* ]]; then # INSTANCE_NAME starts with CONF_APP_NAME
    suffix="${INSTANCE_NAME#*${CONF_APP_NAME}}"
    if [ -z "${suffix##*[!0-9]*}" ]; then # suffix is NOT numeric
      log "Invalid instance name: ${INSTANCE_NAME} \
           \nInstance name must conform to: ${CONF_APP_NAME}<number> (e.g. ${CONF_APP_NAME}1, ${CONF_APP_NAME}2, ...)"
      exit 1
    fi
  fi

  if [ -d ${INSTANCE_HOME} ]; then
    log "Home directory of '${INSTANCE_NAME}' instance already exists: '${INSTANCE_HOME}'"
    exit 1
  fi

  local node_of_instance=`getNodeOfInstance ${INSTANCE_NAME}`
  if [[ "${node_of_instance}" != "" && "${node_of_instance}" != "${NODE_NAME}" ]] ; then
    log "'${INSTANCE_NAME}' instance is not attached to this host('${NODE_NAME}')\
         \nin 'farm.conf'. It is attached to node '${node_of_instance}' instead. \
         \n\nHint: You should either update 'farm.conf' or issue command './instance.sh ${INSTANCE_NAME} ${command}' on node '${node_of_instance}'."
    exit 1
  fi

  if [ ! -d "${CONF_JAVA_HOME}" ]; then
    log "'${CONF_JAVA_HOME}' directory does not exist. Please make sure \
         you installed Java and 'CONF_JAVA_HOME' in 'farm.conf' points to \
         correct path"
    exit 1
  fi

  log "The instance is being created..."

  # Create instance's home directory and sub directories.
  mkdir -p ${INSTANCE_HOME}
  mkdir -p ${INSTANCE_HOME}/lib
  mkdir -p ${INSTANCE_HOME}/logs

  # If not exist, create a symbolic link in logs directory that references to 
  # instance's logs directory.
  if [ ! -L ${CONF_APP_HOME}/logs/${INSTANCE_NAME} ]; then 
    ln -s ${INSTANCE_HOME}/logs ${CONF_APP_HOME}/logs/${INSTANCE_NAME}
  fi

  log "The instance has been created, but not started. Before starting it up, please;\
       \n - add '${INSTANCE_NAME}' to '${NODE_NAME}' in 'CONF_NODE_INSTANCES' variable of 'farm.conf' on all the nodes,\
       \n - deploy 'app.zip' by executing './instance.sh ${INSTANCE_NAME} deploy' command."

}


# ------------------------------------------------------------------------------
# Deletes the instance on the current node, if it exists and does not run.
#
# It also deletes the symbolic link in 'logs' directory which references to the
# instance's log directory.
# ------------------------------------------------------------------------------
delete () {

  if [[ `isAlive` = "true" ]]; then
    log "The instance cannot be deleted while it is running."
    exit 1
  fi

  log "The instance is being deleted..."

  if [ -d ${INSTANCE_HOME} ]; then
    rm -rf ${INSTANCE_HOME}
    log "The instance's home ('${INSTANCE_HOME}') has been deleted."
  else
    log "Home directory of the instance does not exist: '${INSTANCE_HOME}'"
  fi

  # If exists, delete the symbolic link in 'logs' directory that references to 
  # instance's 'logs' directory.
  if [ -L ${CONF_APP_HOME}/logs/${INSTANCE_NAME} ]; then 
    rm ${CONF_APP_HOME}/logs/${INSTANCE_NAME}
    log "'${CONF_APP_HOME}/logs/${INSTANCE_NAME}' symbolic link has been deleted."
  else
    log "'${CONF_APP_HOME}/logs/${INSTANCE_NAME}' symbolic link does not exist."
  fi

  log "\n\nThe instance has been deleted. Please remove '${INSTANCE_NAME}' from\
       \n'${NODE_NAME}' in 'CONF_NODE_INSTANCES' variable of 'farm.conf'\
       \non all the nodes."

}


usage () {
 
  local usage_help="\n---------------------------------------------------------------- \
    \nUsage \
    \n---------------------------------------------------------------- \
    \n\n./instance.sh <instance_name> <command> \
    \n\nCommands: \
    \n\n  archive-logs            : Archives the instance's log files if it is not running. \
    \n\n  create                  : Creates (but does not start) an instance on the current node, \
    \n                            if it does not already exist on any nodes and its name conforms to \
    \n                            ${CONF_APP_NAME}<number> pattern. (e.g. myapp01, myapp17, etc.) \
    \n\n  delete                  : Deletes the instance on the current node, if it exists and does not run. \
    \n\n  delete-logs             : Deletes the instance's log files if it is not running. \
    \n\n  deploy                  : Deploys 'app.zip', if the instance is not running. \
    \n\n  take-thread-dump        : Takes thread dump from instance's JVM. \
    \n\n  is-alive                : Returns 'true' if the instance is running and 'false' otherwise. \
    \n\n  restart                 : Stops and then starts the instance. \
    \n\n  restart-verify          : Stops and then starts the instance. It blocks until the instance \
    \n                            has been started successfully or an error occurs. \
    \n\n  show-log                : Opens the instance's log file with 'less' command. \
    \n\n  start                   : Archives the instance's logs, then starts it. It neither blocks nor \
    \n                            checks for failures while the instance is starting up. \
    \n\n  start-memusage-recording: Starts to record memory usage data of the instance. \
    \n\n  start-verify            : Archives the instance's logs, then starts it. It blocks until \
    \n                            the instance has been started successfully or an error occurs. \
    \n\n  status                  : Logs status of the instance (running or not). \
    \n\n  stop                    : Stops the instance. Process is killed if it does not stop in \
    \n                            ${CONF_SHUTDOWN_TIMEOUT_SECONDS} seconds. \
    \n\n  stop-memusage-recording : Stops to record memory usage data of the instance. \
    \n\n  tail-log                : Tails the instance's log file. Ctrl+C can be used to exit. \
    \n\nExamples:  \
    \n\n  ./instance.sh ${CONF_APP_NAME}1 start-verify \
    \n  ./instance.sh ${CONF_APP_NAME}1 stop \
    \n  ./instance.sh ${CONF_APP_NAME}1 deploy \
    \n  ./instance.sh ${CONF_APP_NAME}1 restart"

  printf "[${CONF_DOMAIN_NAME}:${NODE_NAME}:${INSTANCE_NAME}] $usage_help\n" >&2

}


# ------------------------------------------------------------------------------
# Makes initialization.
# ------------------------------------------------------------------------------
# Parameters:
#   $1: instance name (required)
#   $2: command (required)
# ------------------------------------------------------------------------------
initialize () {

  INSTANCE_NAME=${1}
  local command=${2}

  if [[ "$INSTANCE_NAME" = "" || "$command" = "" ]] ; then
    echo "Instance name and command must be entered."
    usage
    exit 1
  fi

  local absolute_path_of_this_file=${0}
  local dir_of_this_file=`dirname $absolute_path_of_this_file`
  local base_sh="${dir_of_this_file}/base.sh"
  if [ ! -f "${base_sh}" ]; then
    echo "'${base_sh}' file does not exist."
    exit 1
  fi

  # Source ${base_sh} to load configuration and enable helper functions such
  # as log().
  . ${base_sh}

  # Extract instance id from instance name.
  #
  # Instance id is a number. By combining application name with instance id, we
  # produce instance name. Therefore, instance names become unique, as well as
  # instance ids. We can obtain instance id from instance name:
  #
  #   INSTANCE_NAME -> CONF_APP_NAME & INSTANCE_ID (e.g. myapp1 -> myapp & 1)
  #
  local instance_id=`echo ${INSTANCE_NAME} | sed -e "s/${CONF_APP_NAME}//g"`

  # Generate application and admin ports.
  #
  # Two ports are used for each instance: application and admin.
  # Port numbers are generated automatically by using CONF_BASE_PORT and
  # instance id(extracted from instance name):
  #
  #   APPLICATION_PORT = CONF_BASE_PORT + (2 * instance_id) - 1
  #   ADMIN_PORT       = CONF_BASE_PORT + (2 * instance_id)
  #
  # For example, if CONF_APP_NAME is myapp and CONF_BASE_PORT is 8000 then;
  #  - instance myapp1's application port is 8001, admin port is 8002.
  #  - instance myapp2's application port is 8003, admin port is 8004.
  #  - ...
  local APPLICATION_PORT=`expr $CONF_BASE_PORT + $instance_id \* 2 - 1`
  local ADMIN_PORT=`expr $CONF_BASE_PORT + $instance_id \* 2`
  
  export APPLICATION_PORT ADMIN_PORT

  # Source ${base_sh} again to insert APPLICATION_PORT and ADMIN_PORT to
  # CONF_JAVA_OPTS
  . ${base_sh}

  INSTANCE_HOME=${CONF_APP_HOME}/instances/${INSTANCE_NAME}

  # Set locale to English/United State UTF-8. If this setting is OK for
  # the application, then there is no need to use JVM arguments such as
  # -Duser.language=en.
  export LC_ALL=en_US.UTF-8

  # Set permissions of directories and files created by the application.
  # Grant 755 to directories and 644 to files.
  umask 022

  if [[ ${command} != "create" ]] ; then

    local nodeOfInstance=`getNodeOfInstance ${INSTANCE_NAME}`
    if [[ "${nodeOfInstance}" = "" ]] ; then
      log "'${INSTANCE_NAME}' instance does not defined in 'farm.conf'."
      exit 1
    fi

    if [[ "${nodeOfInstance}" != "${NODE_NAME}" ]] ; then
      log "'${INSTANCE_NAME}' instance is not attached to this host('${NODE_NAME}')\
           \nin 'farm.conf'. It is attached to '${nodeOfInstance}' node instead. \
           \n'./instance.sh ${INSTANCE_NAME} ${command}' command can only be executed on '${nodeOfInstance}' node."
      exit 1
    fi

    if [ ! -d ${INSTANCE_HOME} ]; then
      log "Although instance '${INSTANCE_NAME}' definition exists in configuration\
           \nfile('farm.conf'), its home directory('${INSTANCE_HOME}') does not\
           \nexist. \
           \n\nYou can create it by issuing the './instance.sh ${INSTANCE_NAME} create' command."
      exit 1
    fi

  fi

  if [[ "$command" = "archive-logs" ]] ; then
    archiveLogs
  elif [[ "$command" = "create" ]] ; then
    create
  elif [[ "$command" = "delete" ]] ; then
    delete
  elif [[ "$command" = "delete-logs" ]] ; then
    deleteLogs
  elif [[ "$command" = "deploy" ]] ; then
    deploy
  elif [[ "$command" = "is-alive" ]] ; then
    isAlive
  elif [[ "$command" = "restart" ]] ; then
    restart
  elif [[ "$command" = "restart-verify" ]] ; then
    restartVerify
  elif [[ "$command" = "show-log" ]] ; then
    showLog
  elif [[ "$command" = "start" ]] ; then
    start
  elif [[ "$command" = "start-memusage-recording" ]] ; then
    startMemUsageRecording
  elif [[ "$command" = "start-verify" ]] ; then
    startVerify
  elif [[ "$command" = "status" ]] ; then
    status
  elif [[ "$command" = "stop" ]] ; then
    stop
  elif [[ "$command" = "stop-memusage-recording" ]] ; then
    stopMemUsageRecording
  elif [[ "$command" = "tail-log" ]] ; then
    tailLog
  elif [[ "$command" = "take-thread-dump" ]] ; then
    takeThreadDump
  else
    log "Unknown command: $command"
    usage
    exit 1
  fi

}


# ------------------------------------------------------------------------------
# The script starts here.
# ------------------------------------------------------------------------------
initialize $1 $2