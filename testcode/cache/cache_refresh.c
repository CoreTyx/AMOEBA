int main(void) {
    volatile unsigned long long cache_line[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    unsigned long long expected = 0;
    unsigned long long observed = 0;

    for (int word = 0; word < 8; word++) {
        expected += cache_line[word];
    }

    for (int access = 0; access < 32; access++) {
        unsigned long long sum = 0;
        for (int word = 0; word < 8; word++) {
            sum += cache_line[word];
        }
        observed += sum;
    }

    return observed == expected * 32 ? 0 : 1;
}