#!/bin/bash

LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"
USER_LIST=$1

# Create /var/secure directory if it does not exist
if [ ! -d /var/secure ]; then
  sudo mkdir -p /var/secure
  sudo chmod 700 /var/secure
fi

# Clear the log file and password file if they exist
: > $LOG_FILE
: > $PASSWORD_FILE

generate_password() {
  openssl rand -base64 12
}

# Process each line in the user list file
while IFS=';' read -r username groups; do
  # Remove leading and trailing whitespaces from username and groups
  username=$(echo "$username" | xargs)
  groups=$(echo "$groups" | xargs)

  echo "Processing user: $username" | tee -a $LOG_FILE

  # Create the personal group for the user if it doesn't exist
  if ! getent group "$username" > /dev/null 2>&1; then
    sudo groupadd "$username"
    echo "Group $username created" | tee -a $LOG_FILE
  else
    echo "Group $username already exists" | tee -a $LOG_FILE
  fi

  # Initialize an array to hold the additional groups
  group_array=()
  for group in $(echo "$groups" | tr ',' ' '); do
    group=$(echo "$group" | xargs)  # Remove any extra whitespace

    # Check if the group exists
    if getent group "$group" > /dev/null 2>&1; then
      group_array+=("$group")
    else
      echo "Invalid group name: $group" | tee -a $LOG_FILE
    fi
  done

  # Join the group array into a comma-separated string
  additional_groups=$(IFS=','; echo "${group_array[*]}")

  # Create the user if they don't exist
  if ! id -u "$username" > /dev/null 2>&1; then
    sudo useradd -m -g "$username" -G "$additional_groups" "$username" &>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "User $username created and added to groups: $additional_groups" | tee -a $LOG_FILE

      # Generate a password for the user
      password=$(generate_password)
      echo "$username:$password" | sudo chpasswd
      if [[ $? -eq 0 ]]; then
        echo "Password for $username set" | tee -a $LOG_FILE

        # Store the password securely (avoid echoing to terminal)
        echo "$username,$password" >> $PASSWORD_FILE
      else
        echo "Failed to set password for user $username" | tee -a $LOG_FILE
      fi

      # Set permissions on the home directory
      sudo chown "$username:$username" "/home/$username"
      sudo chmod 700 "/home/$username"
      echo "Home directory permissions set for $username" | tee -a $LOG_FILE
    else
      echo "Failed to create user $username" | tee -a $LOG_FILE
    fi
  else
    echo "User $username already exists" | tee -a $LOG_FILE

    # Add the user to the additional groups
    sudo usermod -aG "$additional_groups" "$username"
    echo "User $username added to groups: $additional_groups" | tee -a $LOG_FILE
  fi

done < "$USER_LIST"

echo "User creation process completed. Logs can be found at $LOG_FILE."
