-- calculate pi using the formula pi = 2 * (1 * 3 * 5 * ... * (2n-1)) / (2 * 4 * 6 * ... * 2n)
local n_max = 100000000
local half_pi = 1.0

for n = 1, n_max do
    half_pi = half_pi * (2.0*n/((2*n)-1))*(2.0*n/((2*n)+1))
    if (n >= 10) and (math.floor(math.log(n, 10)) % 1 == 0) then
        local full_pi = half_pi * 2
        -- print only if log10(n) is integer
        if (math.log(n, 10) % 1 == 0) then
            print(string.format("(n=%9d) pi=%.10f math.pi=%.10f diff=%.6f%%", n, full_pi, math.pi, math.abs(100*(full_pi-math.pi)/math.pi)))
        end
    end
end

