/**
 * Test the search API.
 */

using Vanubi;

StringSearchIndex idx;

void setup () {
	idx = new StringSearchIndex ();
	var doc1 = new StringSearchDocument ("foo", {"bar", "baz"});
	var doc2 = new StringSearchDocument ("test", {"foo", "qux"});
	idx.index_document (doc1);
	idx.index_document (doc2);
}

void test_simple () {
	setup ();

	var result = idx.search ("bar baz");
	assert (result.length () == 1);

	result = idx.search ("test qux");
	assert (result.length () == 1);

	result = idx.search ("test foo bar");
	assert (result.length () == 2);
}

void test_synonyms () {
	setup ();

	var result = idx.search ("syn");
	assert (result.length () == 0);

	idx.synonyms["foo"] = "syn";

	result = idx.search ("syn");
	assert (result.length () == 0);
}

int main (string[] args) {
	Test.init (ref args);

	Test.add_func ("/search/simple", test_simple);
	Test.add_func ("/search/synonyms", test_synonyms);

	return Test.run ();
}