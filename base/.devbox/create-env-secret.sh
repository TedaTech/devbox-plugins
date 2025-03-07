
# Function to display usage instructions
usage() {
  echo "Usage: $0 --name <secret-name> --namespace <namespace> [--from-env-file <env-file>] [--from-env-file <env-file>] ..." >&2
  echo >&2
  echo "Creates a Kubernetes secret from one or more environment files." >&2
  echo "Later files override values from earlier files." >&2
  echo >&2
  echo "Options:" >&2
  echo "  --name <secret-name>       Name of the Kubernetes secret" >&2
  echo "  --namespace <namespace>    Kubernetes namespace for the secret" >&2
  echo "  --from-env-file <env-file> Path to .env file (can be specified multiple times)" >&2
  exit 1
}

# Initialize variables
SECRET_NAME=""
NAMESPACE=""
ENV_FILES=()

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --from-env-file)
      if [[ ! -f "$2" ]]; then
        echo "Error: Environment file '$2' not found" >&2
        exit 1
      fi
      ENV_FILES+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# Validate required parameters
if [[ -z "$SECRET_NAME" ]]; then
  echo "Error: Secret name is required" >&2
  usage
fi

if [[ -z "$NAMESPACE" ]]; then
  echo "Error: Namespace is required" >&2
  usage
fi

if [[ ${#ENV_FILES[@]} -eq 0 ]]; then
  echo "Error: At least one environment file is required" >&2
  usage
fi

# Create a temporary file to store the combined environment variables
TEMP_ENV_FILE=$(mktemp)
trap 'rm -f "$TEMP_ENV_FILE"' EXIT

# Process all environment files in order
declare -A ENV_VARS
declare -A ENV_KEYS_IN_FILES
for ENV_FILE in "${ENV_FILES[@]}"; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^\s*# || "$line" =~ ^\s*$ ]]; then
      continue
    fi

    # Split the line into key and value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      KEY="${BASH_REMATCH[1]}"
      VALUE="${BASH_REMATCH[2]}"

      # Trim whitespace from key
      KEY=$(echo "$KEY" | tr -d '[:space:]')

      # Skip empty keys
      if [[ -z "$KEY" ]]; then
        continue
      fi

      # Handle quoted values (strip quotes)
      VALUE=$(echo "$VALUE" | sed -E 's/^["\x27](.*)[""\x27]$/\1/')

      # Store in associative array (later files override earlier ones)
      ENV_VARS["$KEY"]="$VALUE"
      # Mark this key as present in files
      ENV_KEYS_IN_FILES["$KEY"]=1
    fi
  done < "$ENV_FILE"
done

# Check for environment variables that should override file values
# but only if the key exists in at least one env file
for KEY in "${!ENV_KEYS_IN_FILES[@]}"; do
  if [[ -n "${!KEY+x}" ]]; then
    ENV_VARS["$KEY"]="${!KEY}"
  fi
done

# Generate kubectl command that outputs a secret YAML
kubectl_cmd="kubectl create secret generic $SECRET_NAME -n $NAMESPACE"

# Add each environment variable as a literal
for KEY in "${!ENV_VARS[@]}"; do
  kubectl_cmd+=" --from-literal=$KEY=\"${ENV_VARS[$KEY]}\""
done

# Add dry-run to output the YAML
kubectl_cmd+=" --dry-run=client -o yaml"

# Execute the command
eval "$kubectl_cmd"