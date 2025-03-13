# Third pass: add all proto files in the same directories as our required files
echo "Adding all proto files from the same directories..."
DIRS_TO_CHECK=$(while read -r proto_file; do
  dirname "$proto_file"
done < "$REQUIRED_LIST" | sort -u)

for dir in $DIRS_TO_CHECK; do
  log_verbose "Adding all proto files from directory: $dir"
  find "$dir" -maxdepth 1 -name "*.proto" | while read -r proto_file; do
    if ! grep -q "^$proto_file$" "$REQUIRED_LIST"; then
      log_verbose "Adding file from same directory: $proto_file"
      echo "$proto_file" >> "$REQUIRED_LIST"
    fi
  done
done#!/bin/sh
# Minimal proto file generator for macOS
# Usage: ./mac_proto_gen.sh <topic_name> <proto_repo_path> <output_repo_path> [--verbose]

# Enable verbose mode if requested
VERBOSE=0
if [ "$4" = "--verbose" ]; then
  VERBOSE=1
fi

# Function to log in verbose mode
log_verbose() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$@"
  fi
}

# Exit on error
set -e

# Check arguments
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <topic_name> <proto_repo_path> <output_repo_path> [--verbose]"
  echo "Example: $0 my-topic ~/proto-repo ~/go-service"
  exit 1
fi

TOPIC="$1"
PROTO_REPO="$2"
OUTPUT_REPO="$3"
MAPPER_FILE="audit_topic_mapper.json"

echo "Starting proto code generation for topic: $TOPIC"
echo "Proto repo: $PROTO_REPO"
echo "Output repo: $OUTPUT_REPO"

# Check if required tools are installed
for cmd in jq protoc; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Error: $cmd is required but not installed"
    exit 1
  fi
done

# Check if the mapper file exists
if [ ! -f "$PROTO_REPO/$MAPPER_FILE" ]; then
  echo "Error: Mapper file not found at $PROTO_REPO/$MAPPER_FILE"
  exit 1
fi

# Create output directory for generated code
GENERATED_DIR="$OUTPUT_REPO/internal/proto/generated"
mkdir -p "$GENERATED_DIR"

# Extract message classes for the topic from the mapper file
echo "Reading topic mapping from $PROTO_REPO/$MAPPER_FILE"

MESSAGE_CLASSES=$(jq -r ".[] | select(.topic == \"$TOPIC\") | .messageTypes[] | .className" "$PROTO_REPO/$MAPPER_FILE")

if [ -z "$MESSAGE_CLASSES" ]; then
  echo "Error: No message classes found for topic '$TOPIC' in the mapper file"
  exit 1
fi

echo "Found message classes for topic '$TOPIC': $MESSAGE_CLASSES"

# Create a temporary build directory - macOS compatible
BUILD_DIR=$(mktemp -d -t proto_build)
echo "Using temporary build directory: $BUILD_DIR"

# Create temp files to store proto paths - macOS compatible
PROTO_LIST=$(mktemp -t proto_list)
IMPORT_LIST=$(mktemp -t import_list)
REQUIRED_LIST=$(mktemp -t required_list)

# Cleanup function
cleanup() {
  echo "Cleaning up temporary files..."
  rm -f "$PROTO_LIST" "$IMPORT_LIST" "$REQUIRED_LIST"
  rm -rf "$BUILD_DIR"
}

# Set up cleanup on exit
trap cleanup EXIT

# Find all proto files in the repo
find "$PROTO_REPO" -name "*.proto" > "$PROTO_LIST"

# For each message class, find the proto file
for message_class in $MESSAGE_CLASSES; do
  echo "Looking for message class: $message_class"
  FOUND=0
  
  while read -r proto_file; do
    if grep -q "message\s\+$message_class\s*{" "$proto_file"; then
      echo "Found $message_class in $proto_file"
      echo "$proto_file" >> "$REQUIRED_LIST"
      FOUND=1
      break
    fi
  done < "$PROTO_LIST"
  
  if [ "$FOUND" -eq 0 ]; then
    echo "Warning: Could not find proto file for message type $message_class"
  fi
done

# Function to extract imports from a proto file
extract_imports() {
  grep -E '^import\s+"[^"]+";' "$1" | sed 's/import\s\+"\([^"]\+\)".*/\1/' || echo ""
}

# Function to find a proto file by its import path
find_proto_file() {
  local import_path="$1"
  local matched_file=""
  
  # Try exact match first
  while read -r proto_file; do
    if echo "$proto_file" | grep -q "/$import_path$"; then
      matched_file="$proto_file"
      break
    fi
  done < "$PROTO_LIST"
  
  # If no exact match, try partial match (for relative imports)
  if [ -z "$matched_file" ]; then
    local import_basename=$(basename "$import_path")
    while read -r proto_file; do
      if echo "$proto_file" | grep -q "/$import_basename$"; then
        matched_file="$proto_file"
        break
      fi
    done < "$PROTO_LIST"
  fi
  
  # If still no match, try just the filename
  if [ -z "$matched_file" ]; then
    local import_basename=$(basename "$import_path")
    while read -r proto_file; do
      if echo "$proto_file" | grep -q "/$import_basename$"; then
        matched_file="$proto_file"
        break
      fi
    done < "$PROTO_LIST"
  fi
  
  echo "$matched_file"
}

# Function to process imports for a file recursively
process_imports() {
  local file="$1"
  
  # Check if file has already been processed
  if grep -q "^$file$" "$REQUIRED_LIST"; then
    return
  fi
  
  # Add file to required list
  echo "$file" >> "$REQUIRED_LIST"
  
  # Process imports
  for import in $(extract_imports "$file"); do
    matched_file=$(find_proto_file "$import")
    if [ -n "$matched_file" ]; then
      process_imports "$matched_file"
    else
      echo "Warning: Could not find proto file for import: $import"
      # Try searching for the file by name
      local import_basename=$(basename "$import")
      echo "Searching for $import_basename by filename..."
      while read -r proto_file; do
        if echo "$proto_file" | grep -q "/$import_basename$"; then
          echo "Found potential match: $proto_file"
          process_imports "$proto_file"
          break
        fi
      done < "$PROTO_LIST"
    fi
  done
}

# Process imports for all initial proto files
echo "Processing imports recursively..."
cp "$REQUIRED_LIST" "$IMPORT_LIST"

# First pass: direct imports from initially found files
while read -r proto_file; do
  process_imports "$proto_file"
done < "$IMPORT_LIST"

# Second pass: look for imports that might be in the same directory level
echo "Looking for additional dependencies at the same directory level..."
while read -r proto_file; do
  # Get the directory of this proto file
  proto_dir=$(dirname "$proto_file")
  log_verbose "Checking directory: $proto_dir"
  
  # Look for other proto files in the same directory that might be dependencies
  find "$proto_dir" -maxdepth 1 -name "*.proto" | while read -r potential_dep; do
    if ! grep -q "^$potential_dep$" "$REQUIRED_LIST"; then
      # Check if this file is imported by any file we already know about
      is_import=0
      while read -r known_file; do
        imports=$(extract_imports "$known_file")
        for import in $imports; do
          if echo "$potential_dep" | grep -q "/$import$" || echo "$potential_dep" | grep -q "/$(basename "$import")$"; then
            is_import=1
            break
          fi
        done
        [ $is_import -eq 1 ] && break
      done < "$REQUIRED_LIST"
      
      if [ $is_import -eq 1 ]; then
        log_verbose "Found dependent file in same directory: $potential_dep"
        process_imports "$potential_dep"
      fi
    fi
  done
done < "$REQUIRED_LIST"

echo "Required proto files:"
cat "$REQUIRED_LIST"

# Determine the proto root directory (for import paths)
PROTO_ROOT="$PROTO_REPO"
echo "Using proto root: $PROTO_ROOT"

# Copy required proto files to build directory
echo "Copying proto files to build directory..."
while read -r proto_file; do
  # Get relative path from proto root
  rel_path="${proto_file#$PROTO_ROOT/}"
  
  # Create directory structure in build directory
  mkdir -p "$BUILD_DIR/$(dirname "$rel_path")"
  
  # Copy the file
  cp "$proto_file" "$BUILD_DIR/$(dirname "$rel_path")/"
done < "$REQUIRED_LIST"

# Run protoc to generate Go code
echo "Generating Go code with protoc..."

# Create a list of all import paths to pass to protoc
IMPORT_PATHS=$(find "$BUILD_DIR" -type d -not -path "$BUILD_DIR" | sort -u | awk -v prefix="--proto_path=" '{print prefix $0}')

# Add the build dir itself as the main import path
IMPORT_PATHS="--proto_path=$BUILD_DIR $IMPORT_PATHS"

find "$BUILD_DIR" -name "*.proto" | xargs protoc \
  $IMPORT_PATHS \
  --go_out="$GENERATED_DIR" \
  --go_opt=paths=source_relative

# Check if we should generate gRPC code
if find "$BUILD_DIR" -name "*.proto" -exec grep -l "service\s\+[A-Za-z0-9_]\+" {} \; | grep -q .; then
  echo "Found service definitions, generating gRPC code..."
  find "$BUILD_DIR" -name "*.proto" | xargs protoc \
    $IMPORT_PATHS \
    --go-grpc_out="$GENERATED_DIR" \
    --go-grpc_opt=paths=source_relative
fi

echo "Done!"
echo ""
echo "Generated files:"
echo "  - Protocol Buffer Go code: $GENERATED_DIR/*.go"
echo ""
echo "Next steps:"
echo "  1. Review the generated code"
echo "  2. Implement your own Kafka consumer in your Go service"
echo "  3. Create message handlers for each message type"
