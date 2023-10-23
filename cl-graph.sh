#!/bin/bash

hashtag=trusty-kernel-rust

tempdir=$(mktemp -dt "cl-graph-${hashtag}-XXXXXXXX")

changes_json_file="$tempdir/changes.json"

# download list of CLs for the hashtag
curl -s "https://android-review.googlesource.com/changes/?q=hashtag:%22${hashtag}%22&o=SUBMIT_REQUIREMENTS" | tail -n -1 > "${changes_json_file}"

# extract CL numbers
numbers=$(<"${changes_json_file}" jq -r .[]._number)

bubble_width=30

declare -A topic_commits;

echo "digraph \"$hashtag\" {"

# download info on each CL
for number in $numbers; do
	commit_json_file="$tempdir/commit-${number}.json"

	curl -s "https://android-review.googlesource.com/changes/${number}/revisions/current/commit" | tail -n -1 > ${commit_json_file}
done

# process CL parents and topics
for number in $numbers; do
	commit_json_file="$tempdir/commit-${number}.json"

	topic=$(<"${changes_json_file}" jq -r ".[] | select(._number == $number).topic")
	subject=$(<${commit_json_file} jq -r .subject | fold -s -w $bubble_width | sed -z -r 's/\n/\\n/g')
	commit=$(<${commit_json_file} jq -r .commit)

	# label CL
	echo "\"$commit\" [label=\"$subject\"];"

	# count failing checks
	failing_checks=$(<"${changes_json_file}" jq -r ".[] | select(._number == $number).submit_requirements | map(.submittability_expression_result.status | select(. == \"FAIL\")) | length")
	# mark ready-to-submit green
	if [ "$failing_checks" == "0" ]; then
		echo "\"$commit\" [fillcolor=\"lightgreen\" style=\"filled\"];"
	elif [ "$failing_checks" == "1" ]; then
		echo "\"$commit\" [fillcolor=\"lightyellow\" style=\"filled\"];"
	fi

	# assign CL to topic
	if [ "$topic" != "null" ]; then
		topic_commits["$topic"]+="\"$commit\";"
	fi

	# link CL to parent commits
	parents=$(<${commit_json_file} tail -n -1 | jq -r .parents[].commit)
	for parent in $parents; do
		# if parent is one of topic's commits, name it, else say project@HEAD
		if cat "$tempdir"/commit-*.json | jq -e -r "select(.commit == \"$parent\")" >/dev/null; then
			echo "\"$commit\" -> \"$parent\";"
		else
			project=$(<${changes_json_file} jq -r ".[] | select(._number == $number).project")
			echo "\"$commit\" -> \"${project}@HEAD\";"
			echo "\"${project}@HEAD\" [fillcolor=\"lightblue\" style=\"filled\"];"
		fi
	done
done

# emit topic clusters
for topic in ${!topic_commits[@]}; do
	echo "subgraph \"cluster_topic:$topic\" {"
	echo "label=\"topic:$topic\";"
	echo "${topic_commits[$topic]}"
	echo "}"
done

echo "}"
